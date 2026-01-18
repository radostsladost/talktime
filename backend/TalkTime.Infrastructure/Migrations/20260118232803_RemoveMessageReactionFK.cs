using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace TalkTime.Infrastructure.Migrations
{
    /// <inheritdoc />
    public partial class RemoveMessageReactionFK : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_reactions_messages_message_id",
                table: "reactions");

            migrationBuilder.AddColumn<string>(
                name: "conversation_id",
                table: "reactions",
                type: "text",
                nullable: false,
                defaultValue: "");

            migrationBuilder.CreateIndex(
                name: "IX_reactions_conversation_id",
                table: "reactions",
                column: "conversation_id");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_reactions_conversation_id",
                table: "reactions");

            migrationBuilder.DropColumn(
                name: "conversation_id",
                table: "reactions");

            migrationBuilder.AddForeignKey(
                name: "FK_reactions_messages_message_id",
                table: "reactions",
                column: "message_id",
                principalTable: "messages",
                principalColumn: "id",
                onDelete: ReferentialAction.Cascade);
        }
    }
}
