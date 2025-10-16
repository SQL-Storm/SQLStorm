-- {"query": "1078.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1960} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.TagName] AS TagPath,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0
    UNION ALL
    SELECT 
        t.Id,
        t.TagName,
        t.Count,
        r.TagPath || t.TagName,
        r.Level + 1
    FROM Tags t
    JOIN RecursiveTagHierarchy r ON t.Id != r.Id AND t.IsModeratorOnly = 0 AND t.IsRequired = 0
    WHERE r.Level < 2 AND NOT t.TagName = ANY(r.TagPath)
),
UserBadgeCounts AS (
    SELECT
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM Badges b
    GROUP BY b.UserId
),
PostAnswerStats AS (
    SELECT 
        p.ParentId AS QuestionId,
        COUNT(*) AS AnswerCount,
        AVG(p.Score) AS AvgAnswerScore,
        MAX(p.Score) AS MaxAnswerScore,
        SUM(COALESCE(vt_scores.UpVotes,0)) - SUM(COALESCE(vt_scores.DownVotes,0)) AS NetVotesOnAnswers
    FROM Posts p
    LEFT JOIN (
        SELECT 
            PostId,
            SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON v.VoteTypeId = vt.Id
        GROUP BY PostId
    ) vt_scores ON vt_scores.PostId = p.Id
    WHERE p.PostTypeId = 2
    GROUP BY p.ParentId
),
QuestionActivity AS (
    SELECT 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        u.Id AS OwnerUserId,
        u.DisplayName,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        COALESCE(pas.AnswerCount,0) AS AnswerCount,
        COALESCE(pas.AvgAnswerScore,0) AS AvgAnswerScore,
        COALESCE(pas.MaxAnswerScore,0) AS MaxAnswerScore,
        COALESCE(pas.NetVotesOnAnswers,0) AS NetVotesOnAnswers,
        ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC, p.ViewCount DESC) AS UserTopQuestionRank,
        COALESCE(pl.LinkedDuplicates, 0) AS LinkedDuplicates,
        COALESCE(closed.ReasonName, 'Open') AS CloseReason
    FROM Posts p
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
    LEFT JOIN PostAnswerStats pas ON pas.QuestionId = p.Id
    LEFT JOIN (
        SELECT 
            pl.PostId,
            COUNT(*) FILTER (WHERE lt.Name = 'Duplicate') AS LinkedDuplicates
        FROM PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
        GROUP BY pl.PostId
    ) pl ON pl.PostId = p.Id
    LEFT JOIN (
        SELECT 
            ph.PostId,
            crt.Name AS ReasonName
        FROM PostHistory ph
        LEFT JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
        LEFT JOIN CloseReasonTypes crt ON ph.Comment::int = crt.Id
        WHERE ph.PostHistoryTypeId = 10 -- Post Closed
    ) closed ON closed.PostId = p.Id
    WHERE p.PostTypeId = 1
),
CommentStats AS (
    SELECT 
        c.PostId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore,
        SUM(CASE WHEN c.UserId IS NULL THEN 1 ELSE 0 END) AS AnonymousComments
    FROM Comments c
    GROUP BY c.PostId
),
FinalStats AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        q.DisplayName AS OwnerDisplayName,
        q.GoldBadges,
        q.SilverBadges,
        q.BronzeBadges,
        q.AnswerCount,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.NetVotesOnAnswers,
        q.UserTopQuestionRank,
        q.LinkedDuplicates,
        q.CloseReason,
        cs.CommentCount,
        COALESCE(cs.AvgCommentScore,0) AS AvgCommentScore,
        cs.AnonymousComments,
        LENGTH(q.Title) - LENGTH(REPLACE(LOWER(q.Title), 'sql', '')) AS SQLKeywordCount,
        CASE 
            WHEN q.CloseReason IS NULL OR q.CloseReason = 'Open' THEN 0 
            ELSE 1 
        END AS IsClosedFlag,
        ROW_NUMBER() OVER (ORDER BY q.Score DESC, q.ViewCount DESC) AS GlobalRank
    FROM QuestionActivity q
    LEFT JOIN CommentStats cs ON cs.PostId = q.Id
)
SELECT 
    fs.QuestionId,
    fs.Title,
    fs.DisplayName || ' (Reputation: ' || COALESCE(u.Reputation,0) || ')' AS OwnerWithReputation,
    fs.CreationDate,
    fs.Score,
    fs.ViewCount,
    fs.Tags,
    fs.AnswerCount,
    ROUND(fs.AvgAnswerScore,2) AS AvgAnswerScore,
    fs.MaxAnswerScore,
    fs.NetVotesOnAnswers,
    fs.CommentCount,
    ROUND(fs.AvgCommentScore,2) AS AvgCommentScore,
    fs.AnonymousComments,
    fs.SQLKeywordCount,
    fs.IsClosedFlag,
    fs.CloseReason,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.UserTopQuestionRank,
    fs.LinkedDuplicates,
    fs.GlobalRank,
    CASE 
        WHEN fs.Score > 100 THEN 'Popular'
        WHEN fs.Score BETWEEN 50 AND 100 THEN 'Moderate'
        ELSE 'Low'
    END AS PopularityClassification,
    -- Correlated subquery: find user display name of last editor of accepted answer if any
    (
        SELECT ua.DisplayName 
        FROM Posts a
        JOIN Users ua ON ua.Id = a.LastEditorUserId
        WHERE a.Id = q.AcceptedAnswerId
        LIMIT 1
    ) AS AcceptedAnswerLastEditor,
    -- Window function to compute running total of views partitioned by owner user ordered by creation date
    SUM(fs.ViewCount) OVER (PARTITION BY fs.OwnerDisplayName ORDER BY fs.CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS RunningViewCountByOwner,
    -- Complex expression involving NULL logic and string functions for tags
    CASE 
        WHEN fs.Tags IS NULL THEN 'No Tags'
        ELSE 
            'TagCount:' || array_length(string_to_array(substring(fs.Tags,2,length(fs.Tags)-2), '><'),1) || '; FirstTag:' || 
            COALESCE(
                (string_to_array(substring(fs.Tags,2,length(fs.Tags)-2), '><'))[1],
                'Unknown'
            )
    END AS TagSummary
FROM FinalStats fs
JOIN Users u ON u.DisplayName = fs.OwnerDisplayName
WHERE fs.AnswerCount > 2
  AND (fs.CloseReason IS NULL OR fs.CloseReason = 'Open')
  AND fs.SQLKeywordCount > 0
ORDER BY fs.GlobalRank
LIMIT 50

UNION

SELECT 
    u.Id AS QuestionId,
    CONCAT('User Summary for ', u.DisplayName) AS Title,
    CONCAT(u.DisplayName, ' (Reputation: ', u.Reputation, ')') AS OwnerWithReputation,
    u.CreationDate,
    NULL AS Score,
    NULL AS ViewCount,
    NULL AS Tags,
    NULL AS AnswerCount,
    NULL AS AvgAnswerScore,
    NULL AS MaxAnswerScore,
    NULL AS NetVotesOnAnswers,
    NULL AS CommentCount,
    NULL AS AvgCommentScore,
    NULL AS AnonymousComments,
    0 AS SQLKeywordCount,
    0 AS IsClosedFlag,
    'N/A' AS CloseReason,
    COALESCE(ubc.GoldBadges,0),
    COALESCE(ubc.SilverBadges,0),
    COALESCE(ubc.BronzeBadges,0),
    NULL AS UserTopQuestionRank,
    NULL AS LinkedDuplicates,
    NULL AS GlobalRank,
    'N/A' AS PopularityClassification,
    NULL AS AcceptedAnswerLastEditor,
    NULL AS RunningViewCountByOwner,
    'N/A' AS TagSummary
FROM Users u
LEFT JOIN UserBadgeCounts ubc ON ubc.UserId = u.Id
WHERE u.Reputation > 5000
ORDER BY u.Reputation DESC
LIMIT 10;
