-- {"query": "1283.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3410}
WITH ActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        LENGTH(COALESCE(u.AboutMe, '')) AS AboutMeLength,
        REPLACE(LOWER(SUBSTRING(u.WebsiteUrl FROM COALESCE(NULLIF(POSITION('://' IN u.WebsiteUrl), 0), 0) + CASE WHEN POSITION('://' IN u.WebsiteUrl) > 0 THEN 3 ELSE 1 END)), '/', '') AS CleanWebsiteDomain
    FROM
        Users u
    WHERE
        u.Reputation > 7500
        AND u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '1 year')
        AND u.Views IS NOT NULL AND u.Views > 100
),
QuestionEngagement AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate AS PostCreationDate,
        COALESCE(p.Score, 0) AS PostScore,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        LOWER(TRIM(SPLIT_PART(SUBSTRING(p.Tags FROM 2 FOR GREATEST(LENGTH(p.Tags) - 2,0)), '><', 1))) AS PrimaryTag,
        (SELECT COUNT(DISTINCT ph_edit.UserId)
         FROM PostHistory ph_edit
         WHERE ph_edit.PostId = p.Id
           AND ph_edit.PostHistoryTypeId IN (4, 5, 6)
           AND ph_edit.CreationDate > p.CreationDate
        ) AS DistinctEditorCount,
        (SELECT COUNT(*)
         FROM PostLinks pl
         WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
        ) AS LinkedPostCount,
        (SELECT COUNT(*)
         FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2
        ) AS UpVoteCount,
        (SELECT COUNT(*)
         FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 3
        ) AS DownVoteCount,
        (SELECT MAX(ph_closed.CreationDate)
         FROM PostHistory ph_closed
         WHERE ph_closed.PostId = p.Id AND ph_closed.PostHistoryTypeId = 10
        ) AS PostHistoryClosedDate
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.CreationDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '3 years')
        AND p.ViewCount > 500
        AND p.Score >= 0
),
QuestionCommentsSummary AS (
    SELECT
        c.PostId,
        COUNT(c.Id) AS TotalCommentsOnPost,
        AVG(c.Score) AS AvgCommentScore,
        MAX(c.CreationDate) AS LatestCommentDate
    FROM Comments c
    GROUP BY c.PostId
),
TagPerformance AS (
    SELECT
        t.TagName,
        t.Count AS GlobalTagUsage,
        SUM(qe.ViewCount) AS TotalViewsForTag,
        AVG(qe.PostScore) AS AvgScoreForTag,
        COUNT(DISTINCT qe.PostId) AS QuestionsWithTag,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC, SUM(qe.ViewCount) DESC) AS TagRank,
        NTILE(5) OVER (ORDER BY SUM(qe.UpVoteCount) DESC) AS UpVoteQuintile
    FROM Tags t
    INNER JOIN QuestionEngagement qe ON t.TagName = qe.PrimaryTag
    WHERE t.Count > 1000
    GROUP BY t.TagName, t.Count
    HAVING COUNT(DISTINCT qe.PostId) > 100
),
UserInfluence AS (
    SELECT
        au.UserId,
        au.DisplayName,
        au.Reputation,
        au.UserCreationDate,
        au.LastAccessDate,
        au.AboutMeLength,
        au.CleanWebsiteDomain,
        qe.PostId,
        qe.Title AS PostTitle,
        qe.PostCreationDate,
        qe.PostScore,
        qe.ViewCount,
        qe.AnswerCount,
        qe.CommentCount,
        qe.FavoriteCount,
        qe.LastEditDate,
        qe.PrimaryTag,
        tp.TagName AS RelatedTagName,
        tp.GlobalTagUsage,
        tp.TagRank,
        tp.UpVoteQuintile,
        qc.TotalCommentsOnPost,
        qc.AvgCommentScore,
        qc.LatestCommentDate,
        qe.DistinctEditorCount,
        qe.LinkedPostCount,
        qe.UpVoteCount,
        qe.DownVoteCount,
        COALESCE(qe.ClosedDate, qe.PostHistoryClosedDate) AS FinalClosedDate,
        (au.Reputation * 0.2 + qe.PostScore * 0.5 + qe.AnswerCount * 0.8 + qe.DistinctEditorCount * 0.3 + qe.FavoriteCount * 0.7) AS CalculatedInfluenceScore,
        DENSE_RANK() OVER (PARTITION BY au.UserId ORDER BY qe.PostCreationDate DESC) AS QuestionRankByUser,
        LEAD(qe.PostCreationDate, 1, CAST('1970-01-01' AS timestamp)) OVER (PARTITION BY au.UserId ORDER BY qe.PostCreationDate) AS NextQuestionDate,
        EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qe.PostCreationDate)) / 86400 AS DaysSinceQuestionCreation
    FROM
        ActiveUsers au
    INNER JOIN QuestionEngagement qe ON au.UserId = qe.OwnerUserId
    LEFT JOIN QuestionCommentsSummary qc ON qe.PostId = qc.PostId
    LEFT JOIN TagPerformance tp ON qe.PrimaryTag = tp.TagName
    WHERE
        qe.PostScore > 5
        AND qe.AnswerCount >= 1
        AND (tp.TagRank <= 10 OR tp.UpVoteQuintile = 1)
        AND qe.Title IS NOT NULL AND LENGTH(qe.Title) > 10
        AND qe.Title ~ '[A-Za-z0-9]'
)
SELECT
    ui.UserId,
    ui.DisplayName,
    ui.Reputation,
    'UserInfluence' AS AnalysisType,
    ui.PostId,
    ui.PostTitle,
    ui.PostCreationDate,
    ui.PostScore,
    ui.ViewCount,
    ui.AnswerCount,
    ui.CommentCount,
    ui.FavoriteCount,
    ui.LastEditDate,
    ui.PrimaryTag,
    ui.RelatedTagName,
    ui.GlobalTagUsage,
    ui.TagRank,
    ui.CalculatedInfluenceScore AS MetricValue,
    ui.QuestionRankByUser AS Rank1,
    ui.NextQuestionDate AS Date1,
    CAST(NULL AS bigint) AS Rank2,
    CAST(NULL AS timestamp) AS Date2,
    ui.DaysSinceQuestionCreation AS NumericValue1,
    ui.AboutMeLength AS NumericValue2,
    ui.CleanWebsiteDomain AS StringValue1,
    CAST(NULL AS varchar(255)) AS StringValue2,
    CASE
        WHEN ui.FinalClosedDate IS NOT NULL AND ui.FinalClosedDate > ui.PostCreationDate THEN 'Closed'
        WHEN ui.AnswerCount > 0 AND ui.PostScore > 10 THEN 'Answered & High Score'
        ELSE 'Open & Active'
    END AS PostStatusClassification,
    ui.UpVoteCount,
    ui.DownVoteCount
FROM
    UserInfluence ui
WHERE
    ui.CalculatedInfluenceScore > 50
    AND ui.QuestionRankByUser <= 3
    AND ui.DaysSinceQuestionCreation BETWEEN 30 AND 730
    AND ui.CleanWebsiteDomain IS NOT NULL
    AND ui.CommentCount > 0
    AND ui.PostId IN (SELECT Id FROM Posts WHERE Body LIKE '%<pre><code>%</pre></code>%')
    AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ui.UserId AND LOWER(b.Name) LIKE '%suffering%')
UNION ALL
SELECT
    qe.OwnerUserId AS UserId,
    COALESCE(au.DisplayName, 'Community') AS DisplayName,
    COALESCE(au.Reputation, 0) AS Reputation,
    'PostActivity' AS AnalysisType,
    qe.PostId,
    qe.Title AS PostTitle,
    qe.PostCreationDate,
    qe.PostScore,
    qe.ViewCount,
    qe.AnswerCount,
    qe.CommentCount,
    qe.FavoriteCount,
    qe.LastEditDate,
    qe.PrimaryTag,
    tp.TagName AS RelatedTagName,
    tp.GlobalTagUsage,
    tp.TagRank,
    (qe.ViewCount * 0.1 + qe.UpVoteCount * 0.5 + qe.DistinctEditorCount * 1.0) AS MetricValue,
    DENSE_RANK() OVER (PARTITION BY tp.TagName ORDER BY qe.UpVoteCount DESC, qe.ViewCount DESC) AS Rank1,
    LEAD(ph_rev.CreationDate, 1, CAST('1970-01-01' AS timestamp)) OVER (PARTITION BY qe.PostId ORDER BY ph_rev.CreationDate) AS Date1,
    COUNT(ph_rev.Id) OVER (PARTITION BY qe.PostId) AS Rank2,
    ph_first_edit.CreationDate AS Date2,
    EXTRACT(EPOCH FROM (CAST('2024-10-01 12:34:56' AS timestamp) - qe.LastEditDate)) / 86400 AS NumericValue1,
    (SELECT COUNT(*) FROM Comments WHERE PostId = qe.PostId AND LENGTH(Text) > 200) AS NumericValue2,
    ph_latest_edit.Comment AS StringValue1,
    REPLACE(qe.Title, ' ', '-') || '-' || SUBSTRING(MD5(CAST(qe.PostId AS text)) FROM 1 FOR 8) AS StringValue2,
    CASE
        WHEN qe.DistinctEditorCount > 3 AND qe.AnswerCount = 0 THEN 'Highly Edited, Unanswered'
        WHEN qe.ClosedDate IS NOT NULL AND qe.PostHistoryClosedDate IS NULL THEN 'Closed by Vote'
        WHEN qe.LinkedPostCount > 2 AND qe.PostScore < 0 THEN 'Linked & Negative Score'
        ELSE 'Other Active Post'
    END AS PostStatusClassification,
    qe.UpVoteCount,
    qe.DownVoteCount
FROM
    QuestionEngagement qe
LEFT JOIN ActiveUsers au ON qe.OwnerUserId = au.UserId
LEFT JOIN TagPerformance tp ON qe.PrimaryTag = tp.TagName
LEFT JOIN PostHistory ph_rev ON qe.PostId = ph_rev.PostId AND ph_rev.PostHistoryTypeId IN (4, 5, 6)
LEFT JOIN (
    SELECT PostId, Comment, CreationDate
    FROM (
        SELECT PostId, Comment, CreationDate,
               ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate DESC) rn
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6)
    ) x
    WHERE rn = 1
) ph_latest_edit ON qe.PostId = ph_latest_edit.PostId
LEFT JOIN (
    SELECT PostId, CreationDate
    FROM (
        SELECT PostId, CreationDate,
               ROW_NUMBER() OVER (PARTITION BY PostId ORDER BY CreationDate ASC) rn
        FROM PostHistory
        WHERE PostHistoryTypeId IN (4,5,6)
    ) x
    WHERE rn = 1
) ph_first_edit ON qe.PostId = ph_first_edit.PostId
WHERE
    qe.PostScore < 5
    AND qe.DistinctEditorCount > 2
    AND qe.LinkedPostCount > 0
    AND (tp.UpVoteQuintile IS NULL OR tp.UpVoteQuintile > 3)
    AND qe.LastEditDate IS NOT NULL
    AND qe.LastEditDate >= (CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '6 months')
    AND qe.PostId IN (SELECT pl_dup.PostId FROM PostLinks pl_dup WHERE pl_dup.LinkTypeId = 3 AND pl_dup.RelatedPostId = qe.PostId)
    AND ph_latest_edit.Comment IS NOT NULL AND ph_latest_edit.Comment LIKE '%fix%'
ORDER BY
    MetricValue DESC, PostCreationDate ASC
LIMIT 1000;