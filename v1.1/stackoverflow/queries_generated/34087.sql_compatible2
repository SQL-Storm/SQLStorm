WITH RecursiveUserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Class,
        b.Name AS BadgeName,
        b.Date,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Date IS NOT NULL
),
TopUserBadges AS (
    SELECT * FROM RecursiveUserBadges WHERE BadgeRank <= 5
),
QuestionAnswerStats AS (
    SELECT 
        p.OwnerUserId,
        COUNT(CASE WHEN pt.Name = 'Question' THEN 1 END) AS NumQuestions,
        COUNT(CASE WHEN pt.Name = 'Answer' THEN 1 END) AS NumAnswers,
        AVG(CASE WHEN pt.Name = 'Question' THEN p.Score END) AS AvgQuestionScore,
        AVG(CASE WHEN pt.Name = 'Answer' THEN p.Score END) AS AvgAnswerScore,
        MAX(CASE WHEN pt.Name = 'Question' THEN p.ViewCount END) AS MaxQuestionViews
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
TopTags AS (
    SELECT
        unnest(string_to_array(substring(p.Tags FROM 2 FOR length(p.Tags) - 2), '><')) AS Tag,
        p.OwnerUserId
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL AND p.Tags <> ''
),
UserPopularTags AS (
    SELECT
        t.OwnerUserId,
        t.Tag,
        COUNT(*) AS TagCount
    FROM TopTags t
    GROUP BY t.OwnerUserId, t.Tag
),
UserLatestActivity AS (
    SELECT 
        u.Id AS UserId,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        MAX(c.CreationDate) AS LastCommentDate,
        MAX(ph.CreationDate) AS LastEditDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    GROUP BY u.Id
),
UserVoteAnalysis AS (
    SELECT
        p.OwnerUserId,
        COUNT(v.Id) FILTER (WHERE vt.Name = 'UpMod') AS UpVotesGiven,
        COUNT(v.Id) FILTER (WHERE vt.Name = 'DownMod') AS DownVotesGiven,
        COUNT(v.Id) FILTER (WHERE vt.Name = 'Favorite') AS FavoritesGiven
    FROM Votes v
    JOIN Posts p ON v.PostId = p.Id
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    WHERE v.UserId IS NOT NULL
    GROUP BY p.OwnerUserId
),
UserPostLinks AS (
    SELECT
        p.OwnerUserId,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS LinkedPostsCount,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicatePostsCount
    FROM PostLinks pl
    JOIN Posts p ON pl.PostId = p.Id
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY p.OwnerUserId
)
SELECT 
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    qs.NumQuestions,
    qs.NumAnswers,
    qs.AvgQuestionScore,
    qs.AvgAnswerScore,
    qs.MaxQuestionViews,
    COALESCE(ua.UpVotesGiven, 0) AS UpVotesGiven,
    COALESCE(ua.DownVotesGiven, 0) AS DownVotesGiven,
    COALESCE(ua.FavoritesGiven, 0) AS FavoritesGiven,
    COALESCE(ul.LastPostActivityDate, u.LastAccessDate) AS LastActivity,
    STRING_AGG(DISTINCT t.Tag, ', ') AS PopularTags,
    COUNT(DISTINCT b.Name) AS BadgeCount,
    COALESCE(pl.LinkedPostsCount, 0) AS LinkedPosts,
    COALESCE(pl.DuplicatePostsCount, 0) AS DuplicatePosts
FROM Users u
LEFT JOIN QuestionAnswerStats qs ON u.Id = qs.OwnerUserId
LEFT JOIN UserVoteAnalysis ua ON u.Id = ua.OwnerUserId
LEFT JOIN UserLatestActivity ul ON u.Id = ul.UserId
LEFT JOIN (
    SELECT OwnerUserId, Tag
    FROM (
        SELECT OwnerUserId, Tag, TagCount,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY TagCount DESC) AS rn
        FROM UserPopularTags
    ) pt
    WHERE rn <= 5
) t ON u.Id = t.OwnerUserId
LEFT JOIN Badges b ON u.Id = b.UserId
LEFT JOIN UserPostLinks pl ON u.Id = pl.OwnerUserId
WHERE u.Reputation > 1000
GROUP BY 
    u.Id, u.DisplayName, u.Reputation,
    qs.NumQuestions, qs.NumAnswers, qs.AvgQuestionScore, qs.AvgAnswerScore, qs.MaxQuestionViews,
    ua.UpVotesGiven, ua.DownVotesGiven, ua.FavoritesGiven,
    ul.LastPostActivityDate, u.LastAccessDate,
    pl.LinkedPostsCount, pl.DuplicatePostsCount
ORDER BY u.Reputation DESC
LIMIT 100;