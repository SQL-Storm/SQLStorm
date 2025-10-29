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
        -- Extract and clean domain from WebsiteUrl, handling NULLs and missing '://'
        REPLACE(LOWER(SUBSTRING(u.WebsiteUrl, COALESCE(POSITION('://' IN u.WebsiteUrl), 0) + CASE WHEN POSITION('://' IN u.WebsiteUrl) > 0 THEN 3 ELSE 1 END)), '/', '') AS CleanWebsiteDomain
    FROM
        Users u
    WHERE
        u.Reputation > 7500
        AND u.LastAccessDate >= (NOW() - INTERVAL '1 year')
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
        -- Extract primary tag, convert to lowercase and trim
        LOWER(TRIM(SPLIT_PART(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><', 1))) AS PrimaryTag,
        -- Correlated subquery: count distinct editors for this question
        (SELECT COUNT(DISTINCT ph_edit.UserId)
         FROM PostHistory ph_edit
         WHERE ph_edit.PostId = p.Id
           AND ph_edit.PostHistoryTypeId IN (4, 5, 6) -- Edit Title, Edit Body, Edit Tags
           AND ph_edit.CreationDate > p.CreationDate -- Only edits after initial creation
        ) AS DistinctEditorCount,
        -- Correlated subquery: count linked posts (type 1)
        (SELECT COUNT(*)
         FROM PostLinks pl
         WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1
        ) AS LinkedPostCount,
        -- Correlated subquery: count upvotes
        (SELECT COUNT(*)
         FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 2
        ) AS UpVoteCount,
        -- Correlated subquery: count downvotes
        (SELECT COUNT(*)
         FROM Votes v
         WHERE v.PostId = p.Id AND v.VoteTypeId = 3
        ) AS DownVoteCount,
        -- Correlated subquery: get the last closed date from PostHistory
        (SELECT MAX(ph_closed.CreationDate)
         FROM PostHistory ph_closed
         WHERE ph_closed.PostId = p.Id AND ph_closed.PostHistoryTypeId = 10 -- Post Closed
        ) AS PostHistoryClosedDate
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1 -- Only questions
        AND p.CreationDate >= (NOW() - INTERVAL '3 years')
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
        ROW_NUMBER() OVER (ORDER BY t.Count DESC, SUM(qe.ViewCount) DESC) AS TagRank, -- Window function: rank tags by usage and views
        NTILE(5) OVER (ORDER BY SUM(qe.UpVoteCount) DESC) AS UpVoteQuintile -- Window function: assign tags to upvote quintiles
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
        COALESCE(qe.ClosedDate, qe.PostHistoryClosedDate) AS FinalClosedDate, -- NULL logic: prefer Posts.ClosedDate, fallback to PostHistory
        -- Complex weighted calculation for user influence
        (au.Reputation * 0.2 + qe.PostScore * 0.5 + qe.AnswerCount * 0.8 + qe.DistinctEditorCount * 0.3 + qe.FavoriteCount * 0.7) AS CalculatedInfluenceScore,
        DENSE_RANK() OVER (PARTITION BY au.UserId ORDER BY qe.PostCreationDate DESC) AS QuestionRankByUser, -- Window function: rank questions per user
        LEAD(qe.PostCreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY au.UserId ORDER BY qe.PostCreationDate) AS NextQuestionDate, -- Window function: get next question date
        EXTRACT(EPOCH FROM (NOW() - qe.PostCreationDate)) / 86400 AS DaysSinceQuestionCreation -- Numeric calculation: age of question in days
    FROM
        ActiveUsers au
    INNER JOIN QuestionEngagement qe ON au.UserId = qe.OwnerUserId
    LEFT JOIN QuestionCommentsSummary qc ON qe.PostId = qc.PostId
    LEFT JOIN TagPerformance tp ON qe.PrimaryTag = tp.TagName
    WHERE
        qe.PostScore > 5
        AND qe.AnswerCount >= 1
        AND (tp.TagRank <= 10 OR tp.UpVoteQuintile = 1) -- Filter by top 10 tags or top 20% by upvotes
        AND qe.Title IS NOT NULL AND LENGTH(qe.Title) > 10
        AND qe.Title LIKE '%[A-Za-z0-9]%' -- Ensure title has alphanumeric content
)
-- Main query part 1: User-centric, focusing on high-impact questions by influential users
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
    NULL::bigint AS Rank2, NULL::timestamp AS Date2, -- NULL padding for UNION ALL
    ui.DaysSinceQuestionCreation AS NumericValue1,
    ui.AboutMeLength AS NumericValue2,
    ui.CleanWebsiteDomain AS StringValue1,
    NULL::varchar(255) AS StringValue2, -- NULL padding for UNION ALL
    CASE
        WHEN ui.FinalClosedDate IS NOT NULL AND ui.FinalClosedDate > ui.PostCreationDate THEN 'Closed'
        WHEN ui.AnswerCount > 0 AND ui.PostScore > 10 THEN 'Answered & High Score'
        ELSE 'Open & Active'
    END AS PostStatusClassification, -- Complex conditional logic
    ui.UpVoteCount,
    ui.DownVoteCount
FROM
    UserInfluence ui
WHERE
    ui.CalculatedInfluenceScore > 50
    AND ui.QuestionRankByUser <= 3 -- Top 3 questions by user
    AND ui.DaysSinceQuestionCreation BETWEEN 30 AND 730 -- Questions created between 1 month and 2 years ago
    AND ui.CleanWebsiteDomain IS NOT NULL -- Users with a website specified
    AND ui.CommentCount > 0
    AND ui.PostId IN (SELECT Id FROM Posts WHERE Body LIKE '%<pre><code>%</pre></code>%') -- Correlated subquery: check for code blocks
    AND NOT EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = ui.UserId AND b.Name ILIKE '%suffering%') -- Correlated subquery: user does not have a specific badge
UNION ALL
-- Main query part 2: Post-centric, focusing on highly active or problematic questions
SELECT
    qe.OwnerUserId AS UserId,
    COALESCE(au.DisplayName, 'Community') AS DisplayName, -- NULL logic: default to 'Community' if owner is not an active user
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
    (qe.ViewCount * 0.1 + qe.UpVoteCount * 0.5 + qe.DistinctEditorCount * 1.0) AS MetricValue, -- Different metric for post activity
    DENSE_RANK() OVER (PARTITION BY tp.TagName ORDER BY qe.UpVoteCount DESC, qe.ViewCount DESC) AS Rank1, -- Window function: rank posts within tags
    LEAD(ph_rev.CreationDate, 1, '1970-01-01'::timestamp) OVER (PARTITION BY qe.PostId ORDER BY ph_rev.CreationDate) AS Date1, -- Window function: next revision date
    COUNT(ph_rev.Id) OVER (PARTITION BY qe.PostId) AS Rank2, -- Window function: total revisions count for the post
    ph_first_edit.CreationDate AS Date2, -- Date of the first edit
    EXTRACT(EPOCH FROM (NOW() - qe.LastEditDate)) / 86400 AS NumericValue1, -- Days since last edit
    (SELECT COUNT(*) FROM Comments WHERE PostId = qe.PostId AND LENGTH(Text) > 200) AS NumericValue2, -- Correlated subquery: number of long comments
    ph_latest_edit.Comment AS StringValue1, -- Correlated subquery: comment of the latest edit
    REPLACE(qe.Title, ' ', '-') || '-' || SUBSTRING(MD5(qe.PostId::text), 1, 8) AS StringValue2, -- String manipulation: custom slug-like string with MD5 hash
    CASE
        WHEN qe.DistinctEditorCount > 3 AND qe.AnswerCount = 0 THEN 'Highly Edited, Unanswered'
        WHEN qe.ClosedDate IS NOT NULL AND qe.PostHistoryClosedDate IS NULL THEN 'Closed by Vote' -- Complex NULL logic
        WHEN qe.LinkedPostCount > 2 AND qe.PostScore < 0 THEN 'Linked & Negative Score'
        ELSE 'Other Active Post'
    END AS PostStatusClassification,
    qe.UpVoteCount,
    qe.DownVoteCount
FROM
    QuestionEngagement qe
LEFT JOIN ActiveUsers au ON qe.OwnerUserId = au.UserId -- Outer join
LEFT JOIN TagPerformance tp ON qe.PrimaryTag = tp.TagName
LEFT JOIN PostHistory ph_rev ON qe.PostId = ph_rev.PostId AND ph_rev.PostHistoryTypeId IN (4, 5, 6) -- All edit history entries
LEFT JOIN (SELECT DISTINCT ON (PostId) PostId, Comment, CreationDate FROM PostHistory WHERE PostHistoryTypeId IN (4,5,6) ORDER BY PostId, CreationDate DESC) ph_latest_edit ON qe.PostId = ph_latest_edit.PostId -- Correlated subquery for latest edit comment
LEFT JOIN (SELECT DISTINCT ON (PostId) PostId, CreationDate FROM PostHistory WHERE PostHistoryTypeId IN (4,5,6) ORDER BY PostId, CreationDate ASC) ph_first_edit ON qe.PostId = ph_first_edit.PostId -- Correlated subquery for first edit date
WHERE
    qe.PostScore < 5
    AND qe.DistinctEditorCount > 2
    AND qe.LinkedPostCount > 0
    AND (tp.UpVoteQuintile IS NULL OR tp.UpVoteQuintile > 3) -- Tags that are not top performers, or untagged
    AND qe.LastEditDate IS NOT NULL
    AND qe.LastEditDate >= (NOW() - INTERVAL '6 months')
    AND qe.PostId IN (SELECT pl_dup.PostId FROM PostLinks pl_dup WHERE pl_dup.LinkTypeId = 3 AND pl_dup.RelatedPostId = qe.PostId) -- Correlated subquery: is a duplicate of another post
    AND ph_latest_edit.Comment IS NOT NULL AND ph_latest_edit.Comment LIKE '%fix%' -- String expression
ORDER BY
    MetricValue DESC, PostCreationDate ASC
LIMIT 1000;
