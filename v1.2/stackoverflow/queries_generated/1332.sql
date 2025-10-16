-- {"query": "1332.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1700} 

WITH RecursiveTagHierarchy AS (
    SELECT 
        t.Id,
        t.TagName,
        CAST(t.TagName AS VARCHAR(4000)) AS FullPath,
        t.Count,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0
    
    UNION ALL
    
    SELECT 
        child.Id,
        child.TagName,
        CONCAT(parent.FullPath, ' > ', child.TagName),
        child.Count,
        parent.Level + 1
    FROM Tags child
    INNER JOIN RecursiveTagHierarchy parent ON child.WikiPostId = parent.Id 
    WHERE child.IsModeratorOnly = 0 AND parent.Level < 3
),

QuestionsWithAnswers AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QCreationDate,
        q.Score AS QScore,
        q.ViewCount,
        ARRAY_REMOVE(REGEXP_SPLIT_TO_ARRAY(TRIM(BOTH '<>' FROM q.Tags), '><'), '') AS TagArray,
        a.Id AS AnswerId,
        a.CreationDate AS ACreationDate,
        a.Score AS AScore,
        a.OwnerUserId AS AnswerOwnerUserId
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),

UserActivities AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(DISTINCT b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COUNT(DISTINCT ph.Id) AS PostEdits,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS TotalUpVotesReceived
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    LEFT JOIN PostHistory ph ON ph.UserId = u.Id
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id AND v.VoteTypeId = 2
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate
),

QuestionsRanked AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.OwnerUserId,
        q.QCreationDate,
        q.QScore,
        q.ViewCount,
        q.TagArray,
        q.AnswerId,
        q.ACreationDate,
        q.AScore,
        q.AnswerOwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY q.QuestionId ORDER BY q.AScore DESC, q.ACreationDate ASC NULLS LAST) AS AnsRank
    FROM QuestionsWithAnswers q
),

AcceptedAnswers AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        a.Id AS AcceptedAnswerId,
        a.OwnerUserId AS AcceptedAnswerUserId,
        CASE WHEN a.Id IS NOT NULL THEN 1 ELSE 0 END AS HasAcceptedAnswer,
        DATEDIFF(second, q.CreationDate, a.CreationDate) AS SecondsToAccept
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId
    WHERE q.PostTypeId = 1
),

DuplicateLinkCounts AS (
    SELECT 
        pl.PostId, COUNT(pl.Id) AS DuplicateCount
    FROM PostLinks pl
    WHERE pl.LinkTypeId = 3
    GROUP BY pl.PostId
),

CloseVotesWithReason AS (
    SELECT DISTINCT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) OVER (PARTITION BY ph.PostId, ph.Comment) AS CloseVotesCount
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id
    WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL
),

FinalSummary AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        u.DisplayName AS QuestionOwner,
        u.Reputation AS QuestionOwnerReputation,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        tagh.FullPath AS TagHierarchy,
        da.HasAcceptedAnswer,
        da.SecondsToAccept,
        dc.DuplicateCount,
        cvr.CloseReason,
        cvr.CloseVotesCount,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.PostEdits,
        ua.TotalUpVotesReceived,
        -- Complex Window Function: ranking questions within their first tag by score and view count
        ROW_NUMBER() OVER (
            PARTITION BY COALESCE(NULLIF(tagh.TagName,''), 'Unknown') 
            ORDER BY q.Score DESC, q.ViewCount DESC
        ) AS RankWithinTag,
        -- Complex String Expression: Title length, and normalized score/view ratio with NULL logic
        LENGTH(q.Title) AS TitleLength,
        CASE 
            WHEN q.ViewCount > 0 THEN ROUND(CAST(q.Score AS NUMERIC) / q.ViewCount, 4)
            ELSE NULL 
        END AS ScoreViewRatio
        
    FROM Posts q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN LATERAL (
        SELECT th.*
        FROM RecursiveTagHierarchy th
        WHERE th.TagName = (regexp_split_to_array(TRIM(BOTH '<>' FROM q.Tags), '><'))[1]
        ORDER BY th.Level DESC
        LIMIT 1
    ) tagh ON TRUE
    LEFT JOIN AcceptedAnswers da ON da.QuestionId = q.Id
    LEFT JOIN DuplicateLinkCounts dc ON dc.PostId = q.Id
    LEFT JOIN CloseVotesWithReason cvr ON cvr.PostId = q.Id
    LEFT JOIN UserActivities ua ON ua.Id = u.Id
    WHERE q.PostTypeId = 1
)

SELECT
    fs.QuestionId,
    fs.Title,
    fs.QuestionOwner,
    fs.QuestionOwnerReputation,
    fs.CreationDate,
    fs.Score,
    fs.ViewCount,
    fs.TagHierarchy,
    COALESCE(fs.HasAcceptedAnswer,0) AS HasAcceptedAnswer,
    fs.SecondsToAccept,
    fs.DuplicateCount,
    COALESCE(fs.CloseReason, 'None') AS CloseReason,
    COALESCE(fs.CloseVotesCount,0) AS CloseVotesCount,
    fs.GoldBadges,
    fs.SilverBadges,
    fs.BronzeBadges,
    fs.PostEdits,
    fs.TotalUpVotesReceived,
    fs.RankWithinTag,
    fs.TitleLength,
    fs.ScoreViewRatio,
    -- Subquery: count of comments text length average on question, with NULL handling
    (
        SELECT AVG(LENGTH(c.Text))
        FROM Comments c
        WHERE c.PostId = fs.QuestionId
    ) AS AvgCommentTextLength,
    -- Correlated Sub-query with EXISTS predicate and NULL logic
    EXISTS (
        SELECT 1 
        FROM Posts a 
        WHERE a.ParentId = fs.QuestionId AND a.Score > fs.Score AND a.PostTypeId = 2
    ) AS HasBetterScoringAnswerThanQuestion,
    -- Use of EXCEPT operator in set operation
    (
        SELECT COUNT(*)
        FROM (
            SELECT v.UserId
            FROM Votes v
            WHERE v.PostId = fs.QuestionId AND v.VoteTypeId = 2 AND v.UserId IS NOT NULL
            
            EXCEPT
            
            SELECT ub.Id
            FROM Users ub
            WHERE ub.Reputation < 1000
        ) AS high_reputation_upvoters
    ) AS HighReputationUpvoterCount
FROM FinalSummary fs
WHERE fs.SecondsToAccept IS NOT NULL
ORDER BY fs.Score DESC, fs.ViewCount DESC
LIMIT 100;
