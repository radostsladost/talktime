using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TalkTime.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class NotificationsToken : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.CreateTable(
                name: "user_firebase_tokens",
                columns: table => new
                {
                    id = table.Column<string>(type: "text", nullable: false),
                    user_id = table.Column<string>(type: "text", nullable: false),
                    token = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: false),
                    device_id = table.Column<string>(type: "character varying(255)", maxLength: 255, nullable: true),
                    device_info = table.Column<string>(type: "character varying(500)", maxLength: 500, nullable: true),
                    created_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: false, defaultValueSql: "CURRENT_TIMESTAMP"),
                    last_used_at = table.Column<DateTime>(type: "timestamp with time zone", nullable: true)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_user_firebase_tokens", x => x.id);
                    table.ForeignKey(
                        name: "FK_user_firebase_tokens_users_user_id",
                        column: x => x.user_id,
                        principalTable: "users",
                        principalColumn: "id",
                        onDelete: ReferentialAction.Cascade);
                });

            migrationBuilder.CreateIndex(
                name: "IX_user_firebase_tokens_token",
                table: "user_firebase_tokens",
                column: "token");

            migrationBuilder.CreateIndex(
                name: "IX_user_firebase_tokens_user_id",
                table: "user_firebase_tokens",
                column: "user_id");

            migrationBuilder.CreateIndex(
                name: "IX_user_firebase_tokens_user_id_device_id",
                table: "user_firebase_tokens",
                columns: new[] { "user_id", "device_id" });
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "user_firebase_tokens");
        }
    }
}
