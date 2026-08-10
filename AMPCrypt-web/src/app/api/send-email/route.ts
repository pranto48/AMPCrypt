/*
 * Copyright (c) IT Support BD (https://itsupport.com.bd). All rights reserved.
 * This file is part of AMPCrypt.
 This program is free software but it under the terms of the GNU Affero General Public License.
 * (This project website link: https://ampcrypt.itsupport.com.bd)
 */

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
  } catch (error: unknown) {
    const message = error instanceof Error ? error.message : "Failed to send email";
    return NextResponse.json({ message }, { status: 500 });
  }
}
