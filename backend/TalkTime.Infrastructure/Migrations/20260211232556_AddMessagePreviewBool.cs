using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TalkTime.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class AddMessagePreviewBool : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "message_preview",
                table: "user_firebase_tokens",
                type: "boolean",
                nullable: false,
                defaultValue: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "message_preview",
                table: "user_firebase_tokens");
        }
    }
}
