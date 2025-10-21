WITH RecentPosts AS (
    SELECT 
        Posts.Id,
        Posts.PostTypeId,
        Posts.AcceptedAnswerId,
        Posts.ParentId,
        Posts.CreationDate,
        Posts.Score,
        Posts.ViewCount,
        Posts.Body,
        Posts.OwnerUserId,
        Posts.OwnerDisplayName,
        Posts.LastEditorUserId,
        Posts.LastEditorDisplayName,
        Posts.LastEditDate,
        Posts.LastActivityDate,
        Posts.Title,
        Posts.Tags,
        Posts.AnswerCount,
        Posts.CommentCount,
        Posts.FavoriteCount,
        Posts.ClosedDate,
        Posts.CommunityOwnedDate,
        Posts.ContentLicense
    FROM Posts
    WHERE Posts.CreationDate > DATE '2024-10-01' - INTERVAL '30 days'
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId,
        Users.DisplayName,
        COUNT(Posts.Id) AS PostCount,
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 1 THEN Posts.Id END) AS QuestionCount,
        COUNT(DISTINCT CASE WHEN Posts.PostTypeId = 2 THEN Posts.Id END) AS AnswerCount
    FROM Users
    LEFT JOIN Posts ON Users.Id = Posts.OwnerUserId
    WHERE Posts.CreationDate > DATE '2024-10-01' - INTERVAL '1 year'
    GROUP BY Users.Id, Users.DisplayName
),
BadgesSummary AS (
    SELECT 
        Badges.UserId,
        COUNT(*) AS TotalBadges,
        SUM(CASE WHEN Badges.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN Badges.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN Badges.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
    FROM Badges
    GROUP BY Badges.UserId
)
SELECT 
    RP.Id AS PostId,
    RP.PostTypeId,
    RP.AcceptedAnswerId,
    RP.ParentId,
    RP.CreationDate,
    RP.Score,
    RP.ViewCount,
    RP.Body,
    RP.OwnerUserId,
    RP.OwnerDisplayName,
    RP.LastEditorUserId,
    RP.LastEditorDisplayName,
    RP.LastEditDate,
    RP.LastActivityDate,
    RP.Title,
    RP.Tags,
    RP.AnswerCount,
    RP.CommentCount,
    RP.FavoriteCount,
    RP.ClosedDate,
    RP.CommunityOwnedDate,
    RP.ContentLicense,
    UA.DisplayName AS UserDisplayName,
    UA.PostCount,
    UA.QuestionCount,
    UA.AnswerCount,
    BS.TotalBadges,
    BS.GoldBadges,
    BS.SilverBadges,
    BS.BronzeBadges
FROM RecentPosts RP
LEFT JOIN UserActivity UA ON RP.OwnerUserId = UA.UserId
LEFT JOIN BadgesSummary BS ON RP.OwnerUserId = BS.UserId
ORDER BY RP.CreationDate DESC, RP.Score DESC;