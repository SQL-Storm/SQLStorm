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
    FROM 
        Posts
    WHERE 
        Posts.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '30' DAY)
),
UserActivity AS (
    SELECT 
        Users.Id AS UserId, 
        Users.DisplayName, 
        COUNT(Posts.Id) AS PostCount, 
        COALESCE(SUM(Posts.Score),0) AS TotalScore, 
        SUM(CASE WHEN Posts.PostTypeId = 1 THEN 1 ELSE 0 END) AS QuestionCount, 
        SUM(CASE WHEN Posts.PostTypeId = 2 THEN 1 ELSE 0 END) AS AnswerCount
    FROM 
        Users
    LEFT JOIN 
        Posts ON Users.Id = Posts.OwnerUserId
    WHERE 
        Posts.CreationDate > (CAST('2024-10-01' AS date) - INTERVAL '365' DAY)
    GROUP BY 
        Users.Id, Users.DisplayName
),
BadgeSummary AS (
    SELECT 
        Badges.UserId, 
        COUNT(Badges.Id) AS BadgeCount
    FROM 
        Badges
    GROUP BY 
        Badges.UserId
),
PostTags AS (
    SELECT 
        Posts.Id, 
        REGEXP_REPLACE(Posts.Tags, '^<|>$', '') AS TagsStr
    FROM 
        Posts
    WHERE 
        Posts.Tags IS NOT NULL
),
TagUsage AS (
    SELECT 
        tag AS TagName, 
        COUNT(*) AS OccurrenceCount
    FROM (
        SELECT 
            Id,
            UNNEST(STRING_TO_ARRAY(TagsStr, '><')) AS tag
        FROM PostTags
    ) t
    GROUP BY tag
),
UserBadges AS (
    SELECT 
        Users.Id AS UserId, 
        Badges.Name AS BadgeName, 
        Badges.Date AS BadgeDate
    FROM 
        Users
    JOIN 
        Badges ON Users.Id = Badges.UserId
),
PostVotesWithType AS (
    SELECT 
        Posts.Id AS PostId, 
        VoteTypes.Name AS VoteTypeName, 
        Votes.UserId, 
        Votes.CreationDate, 
        Votes.BountyAmount
    FROM 
        Votes
    JOIN 
        VoteTypes ON Votes.VoteTypeId = VoteTypes.Id
    JOIN 
        Posts ON Votes.PostId = Posts.Id
)
SELECT 
    RecentPosts.Id AS PostId, 
    RecentPosts.PostTypeId, 
    RecentPosts.AcceptedAnswerId, 
    RecentPosts.ParentId, 
    RecentPosts.CreationDate, 
    RecentPosts.Score, 
    RecentPosts.ViewCount, 
    RecentPosts.Body, 
    RecentPosts.OwnerUserId, 
    RecentPosts.OwnerDisplayName, 
    RecentPosts.LastEditorUserId, 
    RecentPosts.LastEditorDisplayName, 
    RecentPosts.LastEditDate, 
    RecentPosts.LastActivityDate, 
    RecentPosts.Title, 
    RecentPosts.Tags, 
    RecentPosts.AnswerCount, 
    RecentPosts.CommentCount, 
    RecentPosts.FavoriteCount, 
    RecentPosts.ClosedDate, 
    RecentPosts.CommunityOwnedDate, 
    RecentPosts.ContentLicense, 
    UserActivity.DisplayName AS ActivityDisplayName, 
    UserActivity.PostCount, 
    UserActivity.TotalScore, 
    UserActivity.QuestionCount, 
    UserActivity.AnswerCount, 
    BadgeSummary.BadgeCount, 
    TagUsage.TagName, 
    TagUsage.OccurrenceCount, 
    UserBadges.BadgeName, 
    UserBadges.BadgeDate, 
    PostVotesWithType.VoteTypeName, 
    PostVotesWithType.UserId AS VoterId, 
    PostVotesWithType.CreationDate AS VoteDate, 
    PostVotesWithType.BountyAmount
FROM 
    RecentPosts
LEFT JOIN 
    UserActivity ON RecentPosts.OwnerUserId = UserActivity.UserId
LEFT JOIN 
    BadgeSummary ON RecentPosts.OwnerUserId = BadgeSummary.UserId
LEFT JOIN 
    PostTags ON RecentPosts.Id = PostTags.Id
LEFT JOIN 
    (
      SELECT pt.Id, UNNEST(STRING_TO_ARRAY(pt.TagsStr, '><')) AS tag
      FROM PostTags pt
    ) ptu ON RecentPosts.Id = ptu.Id
LEFT JOIN 
    TagUsage ON ptu.tag = TagUsage.TagName
LEFT JOIN 
    UserBadges ON RecentPosts.OwnerUserId = UserBadges.UserId
LEFT JOIN 
    PostVotesWithType ON RecentPosts.Id = PostVotesWithType.PostId
ORDER BY 
    RecentPosts.CreationDate DESC, 
    RecentPosts.Score DESC;