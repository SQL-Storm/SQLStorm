-- {"query": "1459.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3375} 
WITH UserEngagementStats AS (
    -- Aggregates user-specific metrics including badge counts and vote activity
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate AS UserLastAccessDate,
        u.UpVotes AS TotalUpVotesGiven,
        u.DownVotes AS TotalDownVotesGiven,
        COUNT(DISTINCT b.Id) AS TotalBadgesCount,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadgesCount,
        SUM(CASE WHEN b.TagBased THEN 1 ELSE 0 END) AS TagBasedBadgesCount,
        AVG(EXTRACT(EPOCH FROM (u.LastAccessDate - u.CreationDate))) AS AvgSecondsBetweenAccessAndCreation, -- Complex date calculation
        (SELECT COUNT(DISTINCT v.PostId) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 5) AS FavoritePostsCount, -- Correlated subquery for favorites
        u.Views
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views
    HAVING COUNT(DISTINCT b.Id) > 0 -- Only users with at least one badge
),
PostContentAnalysis AS (
    -- Analyzes post content, comments, and history for specific patterns
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        LENGTH(p.Body) AS BodyCharLength,
        LENGTH(p.Title) AS TitleCharLength,
        p.Tags,
        p.FavoriteCount,
        COUNT(DISTINCT c.Id) AS TotalCommentCount,
        SUM(CASE WHEN c.UserId IS NOT NULL THEN 1 ELSE 0 END) AS RegisteredUserCommentCount,
        MAX(CASE WHEN ph.PostHistoryTypeId = 5 THEN ph.CreationDate ELSE NULL END) AS LastBodyEditDate, -- Latest body edit
        MAX(CASE WHEN ph.PostHistoryTypeId = 6 THEN ph.CreationDate ELSE NULL END) AS LastTagEditDate, -- Latest tag edit
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpvoteCount, -- Correlated subquery for upvotes
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS DownvoteCount
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    WHERE p.Body IS NOT NULL AND p.Title IS NOT NULL AND p.OwnerUserId IS NOT NULL
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.Score, p.ViewCount, p.Body, p.Title, p.Tags, p.FavoriteCount
),
QuestionAnswerRelations AS (
    -- Links questions to their accepted answers and related posts
    SELECT
        q.Id AS QuestionId,
        q.AcceptedAnswerId,
        qa.OwnerUserId AS AnswerOwnerUserId,
        qa.Score AS AnswerScore,
        COALESCE(STRING_AGG(DISTINCT t.TagName, ';') FILTER (WHERE t.TagName IS NOT NULL), 'NoTags') AS QuestionTagsList, -- String aggregation for tags
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 1) AS LinkedPostsCount,
        COUNT(DISTINCT pl.RelatedPostId) FILTER (WHERE pl.LinkTypeId = 3) AS DuplicatePostsCount
    FROM Posts q
    LEFT JOIN Posts qa ON q.AcceptedAnswerId = qa.Id AND qa.PostTypeId = 2 -- Only answers
    LEFT JOIN PostLinks pl ON q.Id = pl.PostId
    LEFT JOIN LATERAL UNNEST(string_to_array(substring(q.Tags, 2, length(q.Tags)-2), '><')) AS tag_name ON TRUE
    LEFT JOIN Tags t ON t.TagName = tag_name
    WHERE q.PostTypeId = 1 -- Only questions
    GROUP BY q.Id, q.AcceptedAnswerId, qa.OwnerUserId, qa.Score
),
HighReputationTagExperts AS (
    -- Identifies users with high reputation and significant contributions to specific tags, using window functions
    SELECT
        ue.UserId,
        ue.DisplayName,
        t.TagName,
        COUNT(p.Id) AS PostsInTag,
        SUM(p.Score) AS TotalTagScore,
        RANK() OVER (PARTITION BY t.TagName ORDER BY SUM(p.Score) DESC, COUNT(p.Id) DESC) AS TagExpertRank
    FROM UserEngagementStats ue
    JOIN Posts p ON ue.UserId = p.OwnerUserId
    JOIN LATERAL UNNEST(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS tag_name ON TRUE
    JOIN Tags t ON t.TagName = tag_name
    WHERE ue.Reputation > 5000 AND p.PostTypeId = 1 -- High-reputation users contributing to questions
    GROUP BY ue.UserId, ue.DisplayName, t.TagName
    HAVING COUNT(p.Id) >= 5
),
UserPostAggregates AS (
    -- Aggregates user-level post stats *before* final join to apply complex HAVING conditions at user level
    SELECT
        pca.OwnerUserId AS UserId,
        COUNT(DISTINCT pca.PostId) AS UserRelevantPostCount,
        SUM(pca.UpvoteCount) AS UserTotalUpvotes,
        SUM(pca.DownvoteCount) AS UserTotalDownvotes,
        MAX(pca.LastBodyEditDate) AS UserLatestPostEditDate
    FROM PostContentAnalysis pca
    WHERE
        pca.PostTypeId = 1 -- Only questions
        AND pca.PostScore > 20
        AND pca.ViewCount > 1000
        AND pca.RegisteredUserCommentCount > 0
        AND (pca.Tags LIKE '%<sql>%' OR pca.Tags LIKE '%<database>%')
    GROUP BY pca.OwnerUserId
    HAVING
        COUNT(DISTINCT pca.PostId) > 1 -- User must have contributed multiple relevant posts
        AND SUM(pca.UpvoteCount) > SUM(pca.DownvoteCount) * 1.5 -- More upvotes than downvotes by a significant margin
        AND MAX(pca.LastBodyEditDate) IS NOT NULL -- At least one post must have been edited
)
-- Main Query (Part 1: Active contributors to popular questions)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    pca.PostId,
    pca.Title,
    pca.PostScore,
    pca.ViewCount,
    pca.FavoriteCount,
    pca.TotalCommentCount,
    pca.RegisteredUserCommentCount,
    qar.QuestionTagsList,
    h.TagName AS TopExpertTag,
    h.PostsInTag AS ExpertTagPostsCount,
    h.TotalTagScore AS ExpertTagTotalScore,
    CAST(pca.PostScore AS NUMERIC) / GREATEST(1, pca.ViewCount) AS CalculatedRatio,
    (pca.UpvoteCount - pca.DownvoteCount) AS NetActivity,
    COALESCE(
        CASE
            WHEN pca.PostScore > 50 AND pca.FavoriteCount > 5 AND pca.ViewCount > 5000 THEN 'HighlyEngaged'
            WHEN pca.TotalCommentCount > 10 OR pca.RegisteredUserCommentCount > 5 THEN 'Discussed'
            WHEN pca.BodyCharLength > 1000 AND pca.TitleCharLength > 50 THEN 'DetailedContent'
            ELSE 'Standard'
        END, 'UnknownCategory'
    ) AS ImpactCategory,
    -- Correlated subquery with NULL logic for last comment by owner
    (SELECT c_corr.Text
     FROM Comments c_corr
     WHERE c_corr.PostId = pca.PostId AND c_corr.UserId = ues.UserId
     ORDER BY c_corr.CreationDate DESC
     LIMIT 1) AS AdditionalInfo,
    -- Window function: Average score of posts by this user within the last year of the post's creation
    AVG(pca.PostScore) OVER (PARTITION BY ues.UserId ORDER BY pca.PostCreationDate RANGE BETWEEN INTERVAL '1 year' PRECEDING AND CURRENT ROW) AS RollingMetric,
    -- Check if the post has been edited recently (within 30 days relative to post creation date)
    (CASE WHEN pca.LastBodyEditDate IS NOT NULL AND pca.LastBodyEditDate > (pca.PostCreationDate - INTERVAL '30 days') THEN TRUE ELSE FALSE END) AS BooleanFlag,
    DATE_TRUNC('month', pca.PostCreationDate) AS TimePeriod
FROM UserEngagementStats ues
INNER JOIN UserPostAggregates upa ON ues.UserId = upa.UserId -- Join with aggregated user data
INNER JOIN PostContentAnalysis pca ON ues.UserId = pca.OwnerUserId -- Re-join to get individual post details
LEFT JOIN QuestionAnswerRelations qar ON pca.PostId = qar.QuestionId
LEFT JOIN HighReputationTagExperts h ON ues.UserId = h.UserId AND h.TagExpertRank = 1 -- Join to get the top expert tag for the user
WHERE
    ues.Reputation > 1000
    AND ues.AvgSecondsBetweenAccessAndCreation > (365 * 24 * 60 * 60) -- Active for at least a year in terms of access
    AND EXISTS (SELECT 1 FROM PostHistory ph_corr WHERE ph_corr.PostId = pca.PostId AND ph_corr.PostHistoryTypeId = 11) -- Correlated subquery: Post was reopened at some point
    AND (
        (qar.AcceptedAnswerId IS NOT NULL AND qar.AnswerScore > 10)
        OR (qar.LinkedPostsCount > 0 AND qar.DuplicatePostsCount = 0)
    )
ORDER BY
    ues.Reputation DESC,
    pca.PostScore DESC,
    RollingMetric DESC
LIMIT 500

UNION ALL -- Use UNION ALL to combine with another distinct dataset

-- Main Query (Part 2: Highly active users contributing many answers, especially to questions that were later closed)
WITH AnswererActivity AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        COUNT(DISTINCT p.Id) AS TotalAnswers,
        SUM(p.Score) AS TotalAnswerScore
    FROM Users u
    JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId = 2 -- Only answers
    GROUP BY u.Id, u.DisplayName, u.CreationDate, u.Reputation
    HAVING COUNT(DISTINCT p.Id) > 5 AND SUM(p.Score) > 10
),
ClosedQuestionAnswers AS (
    SELECT
        p.Id AS AnswerId,
        p.OwnerUserId AS AnswerOwnerId,
        p.Score AS AnswerScore,
        p.CreationDate AS AnswerCreationDate,
        q.Id AS QuestionId,
        q.Title AS QuestionTitle,
        q.ClosedDate AS QuestionClosedDate,
        COALESCE(
            (SELECT crt.Name FROM PostHistory ph JOIN CloseReasonTypes crt ON CAST(ph.Comment AS SMALLINT) = crt.Id WHERE ph.PostId = q.Id AND ph.PostHistoryTypeId = 10 ORDER BY ph.CreationDate DESC LIMIT 1),
            'Unknown'
        ) AS LatestCloseReasonName, -- Correlated subquery for close reason
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 1) AS AcceptedVoteCount, -- Accepted by originator
        (SELECT COUNT(DISTINCT v.Id) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) AS AnswerDownvoteCount
    FROM Posts p
    JOIN Posts q ON p.ParentId = q.Id
    WHERE p.PostTypeId = 2 AND q.PostTypeId = 1 AND q.ClosedDate IS NOT NULL -- Answers to closed questions
)
SELECT
    aa.UserId,
    aa.DisplayName,
    aa.Reputation,
    cqa.AnswerId AS PostId,
    cqa.QuestionTitle AS Title, -- Use Question title for context
    cqa.AnswerScore AS PostScore,
    CAST(NULL AS INT) AS ViewCount,
    CAST(NULL AS INT) AS FavoriteCount,
    (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.PostId = cqa.AnswerId) AS TotalCommentCount,
    CAST(NULL AS INT) AS RegisteredUserCommentCount,
    CAST(NULL AS TEXT) AS QuestionTagsList,
    CAST(NULL AS VARCHAR) AS TopExpertTag,
    CAST(NULL AS INT) AS ExpertTagPostsCount,
    CAST(NULL AS INT) AS ExpertTagTotalScore,
    CAST(cqa.AnswerScore AS NUMERIC) / (GREATEST(1, cqa.AcceptedVoteCount + 1)) AS CalculatedRatio, -- Specific ratio for answers
    (cqa.AcceptedVoteCount - cqa.AnswerDownvoteCount) AS NetActivity,
    CAST('AnswerToClosedQuestion' AS TEXT) AS ImpactCategory,
    cqa.LatestCloseReasonName AS AdditionalInfo,
    -- Window function: Rolling average answer score for the user over the last 6 months
    AVG(cqa.AnswerScore) OVER (PARTITION BY aa.UserId ORDER BY cqa.AnswerCreationDate RANGE BETWEEN INTERVAL '6 months' PRECEDING AND CURRENT ROW) AS RollingMetric,
    (CASE WHEN cqa.QuestionClosedDate IS NOT NULL AND cqa.AnswerCreationDate < cqa.QuestionClosedDate THEN TRUE ELSE FALSE END) AS BooleanFlag,
    DATE_TRUNC('month', cqa.AnswerCreationDate) AS TimePeriod
FROM AnswererActivity aa
JOIN ClosedQuestionAnswers cqa ON aa.UserId = cqa.AnswerOwnerId
WHERE
    aa.Reputation > 2000
    AND cqa.AnswerScore > 5
    AND cqa.AcceptedVoteCount > 0 -- Answer was accepted
    AND cqa.QuestionClosedDate IS NOT NULL
ORDER BY
    aa.Reputation DESC,
    cqa.AnswerScore DESC
LIMIT 200;