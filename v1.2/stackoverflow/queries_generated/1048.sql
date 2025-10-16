-- {"query": "1048.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1469} 

WITH RECURSIVE UserBadgeScore AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY b.Date DESC NULLS LAST) AS LastBadgeRank,
        MAX(b.Date) AS LastBadgeDate
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
PostScores AS (
    SELECT 
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        p.CreationDate,
        p.Tags,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        COUNT(*) OVER (PARTITION BY p.PostTypeId) AS TotalCount
    FROM Posts p
    LEFT JOIN PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId IN (1, 2)
),
TopPostsWithComments AS (
    SELECT 
        ps.PostId,
        ps.PostTypeId,
        ps.PostTypeName,
        ps.OwnerUserId,
        ps.OwnerDisplayName,
        ps.Title,
        ps.Score,
        ps.ViewCount,
        ps.AnswerCount,
        ps.CreationDate,
        ps.Tags,
        COALESCE(c.CommentCount, 0) AS CommentCount,
        -- Correlated subquery for average comment score per post
        (
            SELECT AVG(c2.Score)
            FROM Comments c2
            WHERE c2.PostId = ps.PostId AND c2.Score IS NOT NULL
        ) AS AvgCommentScore,
        -- Window function for rank within tag popularity
        RANK() OVER (PARTITION BY unnest(string_to_array(substring(ps.Tags, 2, length(ps.Tags)-2), '><')) ORDER BY ps.Score DESC) AS TagScoreRank
    FROM PostScores ps
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS CommentCount
        FROM Comments
        GROUP BY PostId
    ) c ON c.PostId = ps.PostId
    WHERE ps.ScoreRank <= 100
),
TagPopularity AS (
    SELECT 
        t.TagName,
        t.Count,
        COALESCE(tp.PostCount, 0) AS PostsWithTagCount,
        tp.AvgScore
    FROM Tags t
    LEFT JOIN (
        SELECT 
            tag,
            COUNT(*) AS PostCount,
            AVG(Score) AS AvgScore
        FROM (
            SELECT p.Id, p.Score, unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag
            FROM Posts p
            WHERE p.PostTypeId = 1
        ) sub
        GROUP BY tag
    ) tp ON tp.tag = t.TagName
),
DuplicateQuestions AS (
    SELECT 
        pl.PostId,
        pl.RelatedPostId,
        p.Title AS OriginalTitle,
        p2.Title AS DuplicateTitle,
        pl.CreationDate,
        rt.Name AS LinkTypeName
    FROM PostLinks pl
    INNER JOIN Posts p ON pl.PostId = p.Id AND p.PostTypeId = 1
    INNER JOIN Posts p2 ON pl.RelatedPostId = p2.Id AND p2.PostTypeId = 1
    INNER JOIN LinkTypes rt ON pl.LinkTypeId = rt.Id
    WHERE pl.LinkTypeId = 3 -- Duplicate link type
),
UserActivityStats AS (
    SELECT 
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT ph.PostId) AS EditsCount,
        COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11) THEN ph.PostId END) AS CloseReopenVotes,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVotesGiven,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVotesGiven,
        MAX(u.LastAccessDate) AS LastAccessDate,
        EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - u.CreationDate))/86400 AS DaysSinceCreation,
        CASE WHEN u.Location IS NOT NULL AND u.Location <> '' THEN TRUE ELSE FALSE END AS HasLocation,
        CASE WHEN u.WebsiteUrl IS NOT NULL AND u.WebsiteUrl <> '' THEN TRUE ELSE FALSE END AS HasWebsite
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.LastAccessDate, u.CreationDate, u.Location, u.WebsiteUrl
)
SELECT 
    up.PostId,
    up.PostTypeName,
    up.Title,
    up.OwnerDisplayName,
    up.Score,
    up.ViewCount,
    up.AnswerCount,
    up.CommentCount,
    ROUND(up.AvgCommentScore::numeric, 2) AS AvgCommentScore,
    STRING_AGG(DISTINCT tp.TagName, ', ') AS Tags,
    tp.Count AS TagGlobalCount,
    tp.PostsWithTagCount,
    tp.AvgScore AS TagAvgPostScore,
    dup.RelatedPostId AS DuplicateOfPostId,
    dup.DuplicateTitle AS DuplicateQuestionTitle,
    dup.CreationDate AS DuplicateLinkDate,
    dup.LinkTypeName,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    ubs.Reputation,
    ubs.LastBadgeDate,
    uas.EditsCount,
    uas.CloseReopenVotes,
    uas.UpVotesGiven,
    uas.DownVotesGiven,
    uas.DaysSinceCreation,
    uas.HasLocation,
    uas.HasWebsite
FROM TopPostsWithComments up
LEFT JOIN TagPopularity tp ON tp.TagName = unnest(string_to_array(substring(up.Tags, 2, length(up.Tags)-2), '><'))
LEFT JOIN DuplicateQuestions dup ON dup.PostId = up.PostId
LEFT JOIN UserBadgeScore ubs ON ubs.UserId = up.OwnerUserId
LEFT JOIN UserActivityStats uas ON uas.UserId = up.OwnerUserId
WHERE (tp.Count > 500 OR tp.PostsWithTagCount > 100)
  AND up.AvgCommentScore IS NOT NULL
ORDER BY up.Score DESC NULLS LAST, up.ViewCount DESC NULLS LAST
LIMIT 50;
