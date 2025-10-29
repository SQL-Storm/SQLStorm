-- {"query": "2037.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1781} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id AS TagId,
        t.TagName,
        t.Count,
        COALESCE(p.ViewCount, 0) AS TagExcerptViewCount,
        1 AS Level,
        ARRAY[t.TagName] AS TagPath
    FROM Tags t
    LEFT JOIN Posts p ON t.ExcerptPostId = p.Id
    WHERE t.Id IS NOT NULL

    UNION ALL

    SELECT 
        t2.Id,
        t2.TagName,
        t2.Count,
        COALESCE(p2.ViewCount, 0),
        r.Level + 1,
        r.TagPath || t2.TagName
    FROM Tags t2
    INNER JOIN RecursiveTagHierarchy r ON t2.Id <> ALL(r.TagPath) -- prevent cycles naively by tag name
    LEFT JOIN Posts p2 ON t2.ExcerptPostId = p2.Id
    WHERE r.Level < 3
),
UserActivity AS (
    SELECT 
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COUNT(DISTINCT ph.Id) AS EditsCount,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.Id END) AS UpVotesGiven,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.Id END) AS DownVotesGiven,
        COUNT(DISTINCT b.Id) AS BadgesEarned,
        MAX(b.Date) AS LastBadgeDate,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC NULLS LAST) AS ReputationRank
    FROM Users u
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.DisplayName IS NOT NULL
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
PostStats AS (
    SELECT 
        p.Id,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        p.Tags,
        u.Id AS OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC NULLS LAST) AS ScoreRank,
        COUNT(c.Id) AS CommentsCount,
        CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        CASE 
            WHEN p.ClosedDate IS NOT NULL THEN 1
            ELSE 0
        END AS IsClosed,
        DATE_PART('epoch', CURRENT_TIMESTAMP - p.CreationDate)/86400.0 AS AgeDays,
        COALESCE(ptClose.Name, 'N/A') AS CloseReason
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN PostTypes pt ON pt.Id = p.PostTypeId
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN PostHistory phClose ON phClose.PostId = p.Id AND phClose.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes ptClose ON ptClose.Id = CAST(phClose.Comment AS SMALLINT) AND phClose.PostHistoryTypeId = 10
    GROUP BY p.Id, p.PostTypeId, pt.Name, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.FavoriteCount, p.Tags, u.Id, u.DisplayName, p.AcceptedAnswerId, p.ClosedDate, ptClose.Name
),
AcceptedAnswersStats AS (
    SELECT 
        a.Id AS AnswerId,
        a.ParentId AS QuestionId,
        a.Score,
        a.CreationDate,
        a.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC NULLS LAST, a.CreationDate ASC) AS AnswerRank
    FROM Posts a
    INNER JOIN Users u ON u.Id = a.OwnerUserId
    WHERE a.PostTypeId = 2
),
UserBadgeStrings AS (
    SELECT 
        b.UserId,
        STRING_AGG(CONCAT(b.Name, '(', CASE b.Class WHEN 1 THEN 'Gold' WHEN 2 THEN 'Silver' WHEN 3 THEN 'Bronze' ELSE 'Unknown' END, ')'), ', ' ORDER BY b.Date DESC) AS BadgesStr
    FROM Badges b
    GROUP BY b.UserId
)
SELECT
    pst.Id AS PostId,
    pst.PostTypeName,
    pst.Score,
    pst.ViewCount,
    pst.AnswerCount,
    pst.FavoriteCount,
    pst.CommentsCount,
    pst.HasAcceptedAnswer,
    pst.IsClosed,
    pst.CloseReason,
    pst.AgeDays,
    ua.DisplayName AS OwnerName,
    ua.Reputation AS OwnerReputation,
    ua.ReputationRank,
    ua.EditsCount AS OwnerEditCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    COALESCE(ubs.BadgesStr, 'No badges') AS OwnerBadges,
    aa.AnswerId AS TopAnswerId,
    aa.Score AS TopAnswerScore,
    aa.OwnerDisplayName AS TopAnswerOwner,
    STRING_AGG(DISTINCT th.TagName, ', ') FILTER (WHERE th.Level = 1) AS Level1Tags,
    STRING_AGG(DISTINCT th.TagName, ', ') FILTER (WHERE th.Level = 2) AS Level2Tags,
    STRING_AGG(DISTINCT th.TagName, ', ') FILTER (WHERE th.Level = 3) AS Level3Tags,
    LENGTH(pst.Tags) - LENGTH(REPLACE(pst.Tags, '><', '')) + 1 AS TagCountEstimate,
    CASE
        WHEN pst.Score > 50 AND pst.ViewCount > 1000 THEN 'High Impact'
        WHEN pst.Score BETWEEN 10 AND 50 THEN 'Moderate Impact'
        ELSE 'Low Impact'
    END AS ImpactCategory
FROM PostStats pst
LEFT JOIN UserActivity ua ON ua.Id = pst.OwnerUserId
LEFT JOIN AcceptedAnswersStats aa ON aa.QuestionId = pst.Id AND aa.AnswerRank = 1
LEFT JOIN RecursiveTagHierarchy th ON pst.Tags IS NOT NULL AND th.TagName = ANY (
    SELECT UNNEST(string_to_array(substring(pst.Tags FROM 2 FOR char_length(pst.Tags)-2), '><'))
)
LEFT JOIN UserBadgeStrings ubs ON ubs.UserId = ua.Id
WHERE pst.PostTypeName = 'Question'
  AND ua.ReputationRank <= 100
  AND (pst.CloseReason IS NULL OR pst.CloseReason = 'N/A')
GROUP BY 
    pst.Id,
    pst.PostTypeName,
    pst.Score,
    pst.ViewCount,
    pst.AnswerCount,
    pst.FavoriteCount,
    pst.CommentsCount,
    pst.HasAcceptedAnswer,
    pst.IsClosed,
    pst.CloseReason,
    pst.AgeDays,
    ua.DisplayName,
    ua.Reputation,
    ua.ReputationRank,
    ua.EditsCount,
    ua.UpVotesGiven,
    ua.DownVotesGiven,
    ubs.BadgesStr,
    aa.AnswerId,
    aa.Score,
    aa.OwnerDisplayName
ORDER BY pst.Score DESC NULLS LAST, pst.ViewCount DESC NULLS LAST
LIMIT 50
UNION
SELECT
    NULL AS PostId,
    'Summary' AS PostTypeName,
    AVG(pst.Score)::INT,
    AVG(pst.ViewCount)::INT,
    AVG(pst.AnswerCount)::INT,
    AVG(pst.FavoriteCount)::INT,
    AVG(pst.CommentsCount)::INT,
    NULL,
    NULL,
    NULL,
    AVG(pst.AgeDays),
    NULL,
    AVG(ua.Reputation)::INT,
    NULL,
    AVG(ua.EditsCount)::INT,
    AVG(ua.UpVotesGiven)::INT,
    AVG(ua.DownVotesGiven)::INT,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM PostStats pst
LEFT JOIN UserActivity ua ON ua.Id = pst.OwnerUserId
WHERE pst.PostTypeName = 'Question'
  AND ua.ReputationRank <= 100
  AND (pst.CloseReason IS NULL OR pst.CloseReason = 'N/A');
