import { NextResponse } from "next/server";

export async function POST(request: Request) {
  try {
    const { to, subject, html } = await request.json();

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Authorization": "Bearer re_6uqukUSr_JhcPeNW5AhY2264TZASygaS9",
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: "AMPCrypt <noreply@itsupport.bd>",
        to,
        subject,
        html,
      }),
    });

    const data = await response.json();
    return NextResponse.json(data, { status: response.status });
  } catch (error: any) {
    return NextResponse.json({ message: error.message || "Failed to send email" }, { status: 500 });
  }
}
