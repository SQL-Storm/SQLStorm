-- {"query": "1609.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2868} 

WITH UserActivitySummary AS (
    -- CTE 1: Summarizes user activity, badge counts, and overall reputation metrics
    SELECT
        u.Id AS UserId,
        COALESCE(u.DisplayName, 'Anonymous User') AS DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes AS UserUpVotesGiven,
        u.DownVotes AS UserDownVotesGiven,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS TotalQuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS TotalAnswersPosted,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        MAX(v_rcvd.CreationDate) FILTER (WHERE v_rcvd.VoteTypeId = 2) AS LastUpVoteReceived,
        MIN(ph.CreationDate) FILTER (WHERE ph.PostHistoryTypeId IN (4, 5, 6)) AS FirstPostEditDate
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Comments c ON u.Id = c.UserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    LEFT JOIN Votes v_rcvd ON p.Id = v_rcvd.PostId AND u.Id = p.OwnerUserId -- Votes received by posts owned by user
    LEFT JOIN PostHistory ph ON u.Id = ph.UserId AND ph.PostHistoryTypeId IN (4, 5, 6) -- User's own edits
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.UpVotes, u.DownVotes, u.Views
),
PostDetailsExtended AS (
    -- CTE 2: Extracts detailed post information, including parsed tags, edit counts, and latest comment date
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        COALESCE(p.Title, SUBSTRING(p.Body, 1, 100) || '...') AS PostTitleOrBodyPreview, -- String expression and NULL logic
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount AS PostCommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6)) AS PostEditCount, -- Correlated subquery for post edits
        (SELECT MAX(c.CreationDate) FROM Comments c WHERE c.PostId = p.Id AND c.UserId IS NOT NULL) AS LatestCommentFromRegisteredUserDate, -- Correlated subquery for latest comment by a registered user
        CASE
            WHEN p.Tags IS NOT NULL AND LENGTH(TRIM(p.Tags)) > 2 THEN
                (string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))[1] -- Primary tag extraction using string_to_array
            ELSE NULL
        END AS PrimaryTag,
        p.ParentId,
        p.AcceptedAnswerId,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Answered'
            ELSE 'Open'
        END AS PostStatusCategory, -- Complicated predicate/expression
        -- Window function: Rank posts by score within their OwnerUserId and PostType
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.CreationDate DESC) AS PostRankByUserType,
        -- Window function: Calculate average score for posts created on the same day by the same user
        AVG(p.Score) OVER (PARTITION BY p.OwnerUserId, DATE_TRUNC('day', p.CreationDate)) AS DailyAvgPostScoreByUser
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) -- Only questions (1) and answers (2)
    AND p.CreationDate >= (CURRENT_DATE - INTERVAL '3 years') -- Limit to recent posts for performance/relevance
),
TagPerformanceMetrics AS (
    -- CTE 3: Aggregates performance metrics per primary tag
    SELECT
        pde.PrimaryTag,
        COUNT(DISTINCT pde.PostId) AS TagPostCount,
        SUM(pde.PostScore) AS TagTotalScore,
        AVG(pde.ViewCount) AS TagAvgViewCount,
        SUM(pde.PostEditCount) AS TagTotalEdits,
        -- Window function: Rank tags by their total score
        RANK() OVER (ORDER BY SUM(pde.PostScore) DESC, COUNT(DISTINCT pde.PostId) DESC) AS TagScoreRank,
        NTILE(5) OVER (ORDER BY SUM(pde.PostScore) DESC) AS TagScoreQuintile -- NTILE window function
    FROM PostDetailsExtended pde
    WHERE pde.PrimaryTag IS NOT NULL
    GROUP BY pde.PrimaryTag
    HAVING COUNT(DISTINCT pde.PostId) > 50 -- Only consider tags with significant activity
)
-- Main query combining results with a UNION ALL to distinguish high-impact questioners and answerers
SELECT
    uas.DisplayName AS ContributorName,
    uas.UserId,
    'Top Questioner' AS ContributorCategory,
    pde.PostId,
    pde.PostTitleOrBodyPreview AS AssociatedPostTitle,
    pde.PostScore,
    pde.ViewCount,
    NULLIF(pde.AnswerCount, 0) AS ValidAnswerCountForQuestion, -- NULL logic (NULLIF)
    pde.PrimaryTag,
    tpm.TagAvgViewCount,
    uas.Reputation,
    uas.TotalQuestionsPosted,
    uas.TotalAnswersPosted,
    uas.GoldBadges,
    pde.PostStatusCategory,
    pde.PostEditCount,
    pde.LatestCommentFromRegisteredUserDate,
    uas.UserUpVotesGiven - uas.UserDownVotesGiven AS NetUserVotesGiven, -- Simple calculation
    (uas.Reputation * 0.05 + uas.TotalQuestionsPosted * 0.1 + pde.PostScore * 0.2 + pde.DailyAvgPostScoreByUser * 0.05) AS OverallQuestionerImpactScore, -- Complex calculation
    'N/A' AS AnswerAcceptanceRate,
    (SELECT COUNT(DISTINCT l.RelatedPostId) FROM PostLinks l WHERE l.PostId = pde.PostId AND l.LinkTypeId = 3) AS DuplicateLinkedPostCount -- Correlated subquery for linked duplicates
FROM UserActivitySummary uas
INNER JOIN PostDetailsExtended pde ON uas.UserId = pde.OwnerUserId
INNER JOIN TagPerformanceMetrics tpm ON pde.PrimaryTag = tpm.PrimaryTag
WHERE
    pde.PostTypeId = 1 -- Only questions
    AND pde.PostRankByUserType <= 5 -- Top 5 questions by score for each user
    AND uas.Reputation > 75000 -- High reputation users
    AND uas.TotalQuestionsPosted >= 25 -- Minimum number of questions
    AND pde.PostScore >= 75 -- Highly scored questions
    AND pde.PostCreationDate BETWEEN (CURRENT_DATE - INTERVAL '2 years') AND CURRENT_DATE -- Recent questions
    AND tpm.TagScoreRank <= 15 -- From top 15 scoring tags
    AND pde.PostStatusCategory IN ('Open', 'Answered') -- Only open or answered questions
    AND EXISTS ( -- Correlated subquery: check if user has made at least one comment on this post in the last year
        SELECT 1
        FROM Comments c_exist
        WHERE c_exist.PostId = pde.PostId
        AND c_exist.UserId = uas.UserId
        AND c_exist.CreationDate > (CURRENT_DATE - INTERVAL '1 year')
    )
    -- Additional predicate: Check if post body contains a specific keyword (string expression)
    AND pde.PostTitleOrBodyPreview LIKE '%query%' OR pde.PostTitleOrBodyPreview LIKE '%database%'

UNION ALL

SELECT
    uas.DisplayName AS ContributorName,
    uas.UserId,
    'Top Answerer' AS ContributorCategory,
    pde.PostId,
    pde.PostTitleOrBodyPreview AS AssociatedPostTitle,
    pde.PostScore,
    pde.ViewCount,
    NULL AS ValidAnswerCountForQuestion, -- N/A for answers themselves
    pde.PrimaryTag,
    tpm.TagAvgViewCount,
    uas.Reputation,
    uas.TotalQuestionsPosted,
    uas.TotalAnswersPosted,
    uas.GoldBadges,
    pde.PostStatusCategory,
    pde.PostEditCount,
    pde.LatestCommentFromRegisteredUserDate,
    uas.UserUpVotesGiven - uas.UserDownVotesGiven AS NetUserVotesGiven,
    (uas.Reputation * 0.07 + uas.TotalAnswersPosted * 0.15 + pde.PostScore * 0.25 + pde.DailyAvgPostScoreByUser * 0.07) AS OverallAnswererImpactScore, -- Complex calculation
    COALESCE(CAST(SUM(CASE WHEN q_parent.AcceptedAnswerId = pde.PostId THEN 1 ELSE 0 END) * 100.0 / COUNT(pde.PostId) AS NUMERIC(5,2)), 0.00) AS AnswerAcceptanceRate, -- Calculation with NULL logic and type casting
    (SELECT COUNT(ph_cl.PostId) FROM PostHistory ph_cl WHERE ph_cl.PostId = pde.ParentId AND ph_cl.PostHistoryTypeId = 10) AS ParentQuestionClosedCount -- Correlated subquery on parent question history
FROM UserActivitySummary uas
INNER JOIN PostDetailsExtended pde ON uas.UserId = pde.OwnerUserId
INNER JOIN TagPerformanceMetrics tpm ON pde.PrimaryTag = tpm.PrimaryTag
LEFT JOIN Posts q_parent ON pde.ParentId = q_parent.Id -- Outer join to get parent question details for answers
WHERE
    pde.PostTypeId = 2 -- Only answers
    AND pde.PostRankByUserType <= 3 -- Top 3 answers by score for each user
    AND uas.Reputation > 40000 -- High reputation answerers
    AND uas.TotalAnswersPosted >= 50 -- Minimum number of answers
    AND pde.PostScore >= 40 -- Highly scored answers
    AND pde.PostCreationDate BETWEEN (CURRENT_DATE - INTERVAL '1.5 years') AND CURRENT_DATE -- More recent answers
    AND tpm.TagScoreQuintile = 1 -- From the top 20% scoring tags
    AND q_parent.AcceptedAnswerId IS NOT NULL -- The answer must be part of a question that has an accepted answer
    AND NOT EXISTS ( -- Correlated subquery: check if this answer has ever received a 'Spam' vote
        SELECT 1
        FROM Votes v_exist
        WHERE v_exist.PostId = pde.PostId
        AND v_exist.VoteTypeId = 12 -- Spam vote type
    )
    -- Complex predicate: check if the answer body contains specific patterns but not others
    AND (pde.PostTitleOrBodyPreview LIKE '%example code%' OR pde.PostTitleOrBodyPreview LIKE '%best practice%')
    AND pde.PostTitleOrBodyPreview NOT LIKE '%deprecated%'

ORDER BY
    ContributorCategory DESC,
    OverallQuestionerImpactScore DESC NULLS LAST, -- NULLS LAST for sorting behavior with NULLs
    OverallAnswererImpactScore DESC NULLS LAST,
    Reputation DESC,
    PostId;
