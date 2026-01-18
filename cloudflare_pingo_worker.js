/**
 * Pingo Cloud Worker - v3.0
 * 功能：提供验证码重置、打卡、配置同步及家长邮件预警逻辑。
 */

export default {
    async fetch(request, env) {
      const url = new URL(request.url);
      const params = url.searchParams;
      const path = url.pathname.toLowerCase();
  
      const corsHeaders = {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, api-key",
      };
  
      if (request.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  
      const email = params.get("email")?.toLowerCase().trim();
      const name = params.get("name")?.trim() || "Admin"; 
  
      // 通用的邮件发送函数
      async function sendEmailViaBrevo(toEmail, subject, htmlContent) {
        const apiKey = (env.BREVO_API_KEY || "").trim();
        if (!apiKey) {
          console.error("BREVO_API_KEY is not set in environment variables.");
          return { ok: false };
        }
        
        const payload = {
          sender: { name: "Pingo Security", email: "security@pingo-echo.com" },
          to: [{ email: toEmail }],
          subject: subject,
          htmlContent: htmlContent
        };
        
        return await fetch("https://api.brevo.com/v3/smtp/email", {
          method: "POST",
          headers: { "api-key": apiKey, "content-type": "application/json" },
          body: JSON.stringify(payload)
        });
      }
  
      try {
        if (!env.PINGO_KV) throw new Error("KV_BINDING_MISSING");
  
        // --- 1. 重置验证码逻辑 ---
        if (path.includes("reset") && email) {
          const code = Math.floor(100000 + Math.random() * 900000).toString();
          await env.PINGO_KV.put(`RESET_${email}`, code, { expirationTtl: 300 });
          const html = `<div style="font-family:sans-serif;padding:20px;"><h2>Pingo 安全验证</h2><p>您的管理密码重置码为：<strong style="color:#007AFF;font-size:24px;">${code}</strong></p></div>`;
          const mailResp = await sendEmailViaBrevo(email, "Pingo 安全验证码", html);
          return new Response(JSON.stringify({ success: mailResp.ok, debug_sent_code: code }), {
            headers: { ...corsHeaders, "Content-Type": "application/json" }
          });
        }
  
        // --- 2. 报平安打卡 ---
        if (path.includes("checkin") && email && name) {
          await env.PINGO_KV.put(`STATUS#${email}#${name}`, Date.now().toString());
          // 打卡成功后，清除该家庭可能存在的“已发送告警邮件”标记，以便下次超时再次提醒
          await env.PINGO_KV.delete(`ALARM_SENT#${email}#${name}`);
          return new Response("OK", { headers: corsHeaders });
        }
  
        // --- 3. 保存配置 ---
        if (path.includes("saveconfig") && email) {
          const familyKey = `FAMILY#${email}`;
          let familyData = await env.PINGO_KV.get(familyKey, "json") || { members: [], pwd: "" };
          
          if (name !== "Admin" && !familyData.members.includes(name)) {
            familyData.members.push(name);
          }
          
          const newPwd = params.get("pwd");
          if (newPwd) familyData.pwd = newPwd;
          await env.PINGO_KV.put(familyKey, JSON.stringify(familyData));
  
          let finalInterval = params.get("interval");
          let finalReminderTime = params.get("reminderTime");
  
          if (name !== "Admin") {
            const adminConfig = await env.PINGO_KV.get(`CONFIG#${email}#Admin`, "json");
            if (adminConfig && adminConfig.interval) {
              finalInterval = adminConfig.interval;
            }
          }
  
          const config = {
            interval: finalInterval,
            reminderTime: finalReminderTime
          };
  
          await env.PINGO_KV.put(`CONFIG#${email}#${name}`, JSON.stringify(config));
          
          if (name === "Admin") {
            for (const member of familyData.members) {
              await env.PINGO_KV.put(`CONFIG#${email}#${member}`, JSON.stringify(config));
            }
          }
          
          return new Response("OK", { headers: corsHeaders });
        }
  
        // --- 4. 获取状态并执行超时自动预警 ---
        if (path.includes("status") && email) {
          const familyData = await env.PINGO_KV.get(`FAMILY#${email}`, "json") || { members: [], pwd: "" };
          const now = Date.now();
          
          const studentDetails = await Promise.all(familyData.members.map(async (m) => {
            const lastCheckinStr = await env.PINGO_KV.get(`STATUS#${email}#${m}`) || "0";
            const lastCheckin = parseInt(lastCheckinStr);
            const config = await env.PINGO_KV.get(`CONFIG#${email}#${m}`, "json") || {};
            const intervalHrs = parseInt(config.interval || "24");
            
            // 后端超时判断逻辑
            const isOverdue = (now - lastCheckin) > (intervalHrs * 3600 * 1000);
            
            if (isOverdue && lastCheckin > 0) {
              const hasSent = await env.PINGO_KV.get(`ALARM_SENT#${email}#${m}`);
              if (!hasSent) {
                const alertHtml = `<div style="font-family:sans-serif;padding:20px;border:2px solid #ff4d4f;">
                  <h2 style="color:#ff4d4f;">⚠️ Pingo 安全报警</h2>
                  <p>家长您好，您的家庭成员 <strong>${m}</strong> 已超过预定的平安报备时间！</p>
                  <p>最后报备时间：${new Date(lastCheckin).toLocaleString()}</p>
                  <p>请立即联系对方确认安全。</p>
                </div>`;
                await sendEmailViaBrevo(email, `【紧急】Pingo 超时告警：${m}`, alertHtml);
                await env.PINGO_KV.put(`ALARM_SENT#${email}#${m}`, "true", { expirationTtl: 3600 });
              }
            }
  
            return { name: m, lastCheckin: lastCheckinStr, config };
          }));
  
          return new Response(JSON.stringify({
            adminPassword: familyData.pwd,
            students: studentDetails
          }), { 
            headers: { ...corsHeaders, "Content-Type": "application/json" } 
          });
        }
  
        return new Response("Pingo Operational v3.0", { headers: corsHeaders });
      } catch (err) {
        return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: corsHeaders });
      }
    }
  };