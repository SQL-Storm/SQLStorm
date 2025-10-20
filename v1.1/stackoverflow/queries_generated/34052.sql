-- {"query": "34052.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 1288} 

WITH RecursiveUserBadges AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        b.Name AS BadgeName,
        b.Class,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC) AS BadgeRank
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE b.Class IN (1, 2, 3)
),
TopUserBadges AS (
    SELECT UserId, DisplayName, BadgeName, Class
    FROM RecursiveUserBadges
    WHERE BadgeRank <= 5
),
HighReputationUsers AS (
    SELECT Id, DisplayName, Reputation
    FROM Users
    WHERE Reputation > 10000
),
PopularQuestions AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        STRING_TO_ARRAY(TRIM(BOTH '<>' FROM p.Tags), '><') AS TagsArray
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Score > 50
      AND p.ViewCount > 10000
      AND p.CreationDate >= NOW() - INTERVAL '1 year'
),
AnswerDetails AS (
    SELECT
        a.Id,
        a.ParentId AS QuestionId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        ROW_NUMBER() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
TopAnswers AS (
    SELECT * FROM AnswerDetails WHERE AnswerRank <= 3
),
VotesSummary AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotesCount,
        SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotesCount,
        SUM(CASE WHEN vt.Name = 'Favorite' THEN 1 ELSE 0 END) AS FavoriteVotesCount
    FROM Votes v
    JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
    GROUP BY v.PostId
),
CommentStats AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentsCount,
        AVG(c.Score) AS AvgCommentScore
    FROM Comments c
    GROUP BY c.PostId
),
UserActivity AS (
    SELECT
        u.Id,
        u.DisplayName,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        MAX(p.CreationDate) AS LastPostDate,
        MAX(c.CreationDate) AS LastCommentDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    WHERE u.Reputation > 5000
    GROUP BY u.Id, u.DisplayName
),
PostLinkCounts AS (
    SELECT 
        pl.PostId,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Linked') AS LinkedCount,
        COUNT(pl.Id) FILTER (WHERE lt.Name = 'Duplicate') AS DuplicateCount
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY pl.PostId
)
SELECT
    pq.Id AS QuestionId,
    pq.Title,
    pq.OwnerUserId,
    u.DisplayName AS QuestionOwnerName,
    pq.Score AS QuestionScore,
    pq.ViewCount AS QuestionViews,
    pq.AnswerCount AS QuestionAnswers,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    ts.UpVotesCount,
    ts.DownVotesCount,
    ts.FavoriteVotesCount,
    cs.CommentsCount,
    ROUND(cs.AvgCommentScore, 2) AS AvgCommentScore,
    plc.LinkedCount,
    plc.DuplicateCount,
    jsonb_agg(
        jsonb_build_object(
            'AnswerId', ta.Id,
            'AnswerOwnerUserId', ta.AnswerOwnerUserId,
            'AnswerOwnerName', auser.DisplayName,
            'AnswerScore', ta.AnswerScore,
            'AnswerCreationDate', ta.AnswerCreationDate
        ) ORDER BY ta.AnswerScore DESC
    ) FILTER (WHERE ta.Id IS NOT NULL) AS TopAnswers,
    jsonb_agg(
        jsonb_build_object(
            'BadgeName', tub.BadgeName,
            'BadgeClass', tub.Class
        ) ORDER BY tub.Class ASC
    ) FILTER (WHERE tub.BadgeName IS NOT NULL) AS TopUserBadges,
    ua.TotalPosts AS QuestionOwnerTotalPosts,
    ua.TotalComments AS QuestionOwnerTotalComments,
    ua.LastPostDate,
    ua.LastCommentDate
FROM PopularQuestions pq
LEFT JOIN Users u ON pq.OwnerUserId = u.Id
LEFT JOIN Tags t ON t.TagName = ANY(pq.TagsArray)
LEFT JOIN VotesSummary ts ON ts.PostId = pq.Id
LEFT JOIN CommentStats cs ON cs.PostId = pq.Id
LEFT JOIN PostLinkCounts plc ON plc.PostId = pq.Id
LEFT JOIN TopAnswers ta ON ta.QuestionId = pq.Id
LEFT JOIN Users auser ON auser.Id = ta.AnswerOwnerUserId
LEFT JOIN TopUserBadges tub ON tub.UserId = pq.OwnerUserId
LEFT JOIN UserActivity ua ON ua.Id = pq.OwnerUserId
GROUP BY 
    pq.Id,
    pq.Title,
    pq.OwnerUserId,
    u.DisplayName,
    pq.Score,
    pq.ViewCount,
    pq.AnswerCount,
    ts.UpVotesCount,
    ts.DownVotesCount,
    ts.FavoriteVotesCount,
    cs.CommentsCount,
    cs.AvgCommentScore,
    plc.LinkedCount,
    plc.DuplicateCount,
    ua.TotalPosts,
    ua.TotalComments,
    ua.LastPostDate,
    ua.LastCommentDate
ORDER BY pq.Score DESC, pq.ViewCount DESC
LIMIT 50;
