-- {"query": "1074.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3596} 

WITH UserEngagement AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserDisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT q.Id) AS QuestionsPosted,
        COUNT(DISTINCT a.Id) AS AnswersPosted,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        SUM(COALESCE(q.Score, 0)) AS TotalQuestionScore,
        SUM(COALESCE(a.Score, 0)) AS TotalAnswerScore,
        COUNT(c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT vp.PostId) AS VotedPostsCount -- Posts user has voted on
    FROM
        Users u
    LEFT JOIN
        Posts q ON u.Id = q.OwnerUserId AND q.PostTypeId = 1 -- Questions
    LEFT JOIN
        Posts a ON u.Id = a.OwnerUserId AND a.PostTypeId = 2 -- Answers
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Votes vp ON u.Id = vp.UserId AND vp.VoteTypeId IN (2, 3) -- UpMod, DownMod
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views
),
PostHistoricalMetrics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        p.Tags,
        COUNT(ph.Id) AS TotalHistoryEvents,
        SUM(CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN 1 ELSE 0 END) AS EditCount, -- Title, Body, Tags edits
        SUM(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS CloseCount,
        SUM(CASE WHEN ph.PostHistoryTypeId = 11 THEN 1 ELSE 0 END) AS ReopenCount,
        MAX(ph.CreationDate) AS LastHistoryEventDate,
        -- Calculate days since last activity, COALESCE to avoid NULL issues for very new posts
        COALESCE(EXTRACT(EPOCH FROM (NOW() - p.LastActivityDate)) / (60 * 60 * 24), 0) AS DaysSinceLastActivity,
        -- Check if post has any "Off-topic" or "Needs clarity" close reason history
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment IN ('2', '102', '103') THEN 1 ELSE 0 END) AS HasProblematicCloseReason,
        -- Calculate time difference between first and last edit for a post
        EXTRACT(EPOCH FROM (MAX(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate ELSE NULL END) - MIN(CASE WHEN ph.PostHistoryTypeId IN (4,5,6) THEN ph.CreationDate ELSE NULL END))) / (60 * 60) AS HoursBetweenFirstAndLastEdit
    FROM
        Posts p
    LEFT JOIN
        PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastActivityDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, p.ClosedDate, p.AcceptedAnswerId, p.ParentId, p.Title, p.Tags
),
QuestionAnswerPerformance AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId AS QuestionOwnerUserId,
        q.CreationDate AS QuestionCreationDate,
        q.ClosedDate AS QuestionClosedDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.Tags AS QuestionTags,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.CreationDate AS AnswerCreationDate,
        a.Score AS AnswerScore,
        a.FavoriteCount AS AnswerFavoriteCount,
        -- Time to answer in minutes
        EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate)) / 60 AS TimeToAnswer_Minutes,
        -- Time to acceptance in minutes (if accepted), use NULLIF to prevent division by zero for unaccepted answers
        NULLIF(CASE WHEN q.AcceptedAnswerId = a.Id THEN EXTRACT(EPOCH FROM (q.LastActivityDate - a.CreationDate)) / 60 ELSE NULL END, 0) AS TimeToAcceptance_Minutes,
        -- Rank answers by score for each question, breaking ties by creation date (earlier wins)
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS AnswerScoreRank,
        -- Check if the question owner also answered their own question
        (q.OwnerUserId = a.OwnerUserId) AS IsSelfAnswer,
        -- Correlated subquery: Check if the answerer has a 'Gold' badge in any tag related to the question
        EXISTS (
            SELECT 1
            FROM Badges b_inner
            WHERE b_inner.UserId = a.OwnerUserId
              AND b_inner.Class = 1
              AND b_inner.TagBased = TRUE
              AND q.Tags IS NOT NULL
              AND EXISTS (
                  SELECT 1
                  FROM UNNEST(string_to_array(SUBSTRING(q.Tags, 2, LENGTH(q.Tags)-2), '><')) AS q_tag
                  WHERE LOWER(b_inner.Name) = LOWER(q_tag)
              )
        ) AS AnswererHasRelatedGoldBadge,
        -- For each answer, find the reputation of the answerer at the time of answer creation (approximated by user creation date)
        (SELECT u_inner.Reputation FROM Users u_inner WHERE u_inner.Id = a.OwnerUserId) AS AnswererReputation
    FROM
        Posts q
    INNER JOIN
        Posts a ON q.Id = a.ParentId AND a.PostTypeId = 2 -- Only answers linked to questions
    WHERE
        q.PostTypeId = 1 -- Ensure 'q' is a question
        AND q.AcceptedAnswerId IS NOT NULL -- Only consider questions with accepted answers
        AND q.ClosedDate IS NULL -- Exclude closed questions for answer performance
),
AggregatedTagMetrics AS (
    SELECT
        tag_name,
        COUNT(DISTINCT PostId) AS TaggedPostsCount,
        AVG(Score) AS AvgTagScore,
        AVG(ViewCount) AS AvgTagViewCount,
        MAX(PostCreationDate) AS LastTaggedPostDate
    FROM (
        SELECT
            p.Id AS PostId,
            p.Score,
            p.ViewCount,
            p.CreationDate AS PostCreationDate,
            -- Split tags and handle potential empty tags string
            UNNEST(string_to_array(TRIM(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags)-2)), '><')) AS tag_name
        FROM Posts p
        WHERE p.Tags IS NOT NULL AND p.PostTypeId = 1
    ) AS TaggedPosts
    WHERE tag_name IS NOT NULL AND tag_name != ''
    GROUP BY tag_name
    HAVING COUNT(DISTINCT PostId) > 500 -- Only consider sufficiently popular tags
)
SELECT
    ue.UserId,
    ue.UserDisplayName,
    ue.Reputation,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.QuestionsPosted,
    ue.AnswersPosted,
    ue.TotalAnswerScore,
    ue.TotalCommentsMade,
    ue.UserProfileViews,
    COALESCE(ue.TotalAnswerScore * 1.0 / NULLIF(ue.AnswersPosted, 0), 0) AS AvgAnswerScorePerUser,
    COALESCE(ue.TotalQuestionScore * 1.0 / NULLIF(ue.QuestionsPosted, 0), 0) AS AvgQuestionScorePerUser,
    -- Window function: Rank users by their average answer score, broken by reputation
    RANK() OVER (ORDER BY COALESCE(ue.TotalAnswerScore * 1.0 / NULLIF(ue.AnswersPosted, 0), 0) DESC, ue.Reputation DESC) AS UserAnswerQualityRank,
    -- Window function: NTILE for distribution of users by total badges (weighted)
    NTILE(5) OVER (ORDER BY (ue.GoldBadges * 100 + ue.SilverBadges * 10 + ue.BronzeBadges) DESC) AS BadgeTier,
    SUM(qap.TimeToAnswer_Minutes) FILTER (WHERE qap.TimeToAnswer_Minutes IS NOT NULL) AS TotalTimeToAnswer,
    AVG(qap.TimeToAnswer_Minutes) FILTER (WHERE qap.TimeToAnswer_Minutes IS NOT NULL) AS AvgTimeToAnswer,
    SUM(qap.TimeToAcceptance_Minutes) FILTER (WHERE qap.TimeToAcceptance_Minutes IS NOT NULL) AS TotalTimeToAcceptance,
    AVG(qap.TimeToAcceptance_Minutes) FILTER (WHERE qap.TimeToAcceptance_Minutes IS NOT NULL) AS AvgTimeToAcceptance,
    SUM(CASE WHEN qap.AnswerScoreRank = 1 THEN 1 ELSE 0 END) AS TopRankedAnswersCount,
    SUM(CASE WHEN qap.IsSelfAnswer THEN 1 ELSE 0 END) AS SelfAnsweredQuestionsCount,
    SUM(CASE WHEN qap.AnswererHasRelatedGoldBadge THEN 1 ELSE 0 END) AS AnswersWithRelatedGoldBadgeCount,
    -- String aggregation of distinct popular tags from questions answered by the user
    (
        SELECT STRING_AGG(DISTINCT atm.tag_name, ', ' ORDER BY atm.tag_name)
        FROM QuestionAnswerPerformance qap_inner
        JOIN (
            SELECT
                q_tags.Id,
                UNNEST(string_to_array(TRIM(SUBSTRING(q_tags.Tags FROM 2 FOR LENGTH(q_tags.Tags)-2)), '><')) AS tag_name
            FROM Posts q_tags
            WHERE q_tags.Tags IS NOT NULL
        ) AS atm ON qap_inner.QuestionId = atm.Id
        WHERE qap_inner.AnswerOwnerUserId = ue.UserId
          AND atm.tag_name IS NOT NULL AND atm.tag_name != ''
          AND atm.tag_name IN (SELECT tag_name FROM AggregatedTagMetrics WHERE TaggedPostsCount > 1000 AND AvgTagScore > 15) -- Only include highly popular & high-score tags
    ) AS TopAnsweredTags,
    -- Complex Influence Score calculation:
    -- Weighted sum of reputation, average answer score, badge quality, responsiveness, top answers, and user profile views.
    (
        ue.Reputation * 0.05 -- Reputation factor
        + COALESCE(ue.TotalAnswerScore * 1.0 / NULLIF(ue.AnswersPosted, 0), 0) * 0.4 -- Average answer score
        + (ue.GoldBadges * 50 + ue.SilverBadges * 10 + ue.BronzeBadges * 1) * 0.2 -- Badge quality
        + (1000.0 / (NULLIF(AVG(qap.TimeToAnswer_Minutes) FILTER (WHERE qap.TimeToAnswer_Minutes IS NOT NULL), 0) + 1)) * 0.1 -- Responsiveness (inverse of avg time to answer)
        + (SUM(CASE WHEN qap.AnswerScoreRank = 1 THEN 1 ELSE 0 END) * 50) * 0.15 -- Top answers count
        + (ue.UserProfileViews * 0.01) * 0.05 -- Profile visibility
        + (SUM(CASE WHEN qap.AnswererHasRelatedGoldBadge THEN 1 ELSE 0 END) * 10) * 0.05 -- Expertise factor
    ) AS InfluenceScore,
    -- Lag/Lead for historical reputation changes (approximated, as Reputation in Users is current)
    -- This part is a conceptual representation as direct historical reputation isn't in schema,
    -- but could be derived from `VoteTypes` and `PostHistory` if full history was captured for rep.
    -- For this query, we'll use `UE.Reputation` and assume this is a point-in-time snapshot.
    -- To make it more complex, let's include a calculated "reputation change proxy"
    (ue.TotalUpVotesGiven - ue.TotalDownVotesGiven) AS NetVotesGiven,
    -- Max/Avg edit counts and problematic posts for any post owned by the user
    SUM(phm.EditCount) AS TotalOwnedPostEditCount,
    MAX(phm.HoursBetweenFirstAndLastEdit) AS MaxHoursBetweenOwnedPostEdits,
    SUM(phm.HasProblematicCloseReason) AS UserOwnedProblematicPostsCount,
    -- Check if the user has questions linking to other popular questions
    EXISTS (
        SELECT 1
        FROM PostLinks pl
        JOIN PostHistoricalMetrics phm_link ON pl.RelatedPostId = phm_link.PostId
        WHERE pl.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = ue.UserId AND PostTypeId = 1)
          AND pl.LinkTypeId = 1 -- Linked posts
          AND phm_link.PostTypeId = 1
          AND phm_link.ViewCount > 50000 AND phm_link.Score > 50
    ) AS LinksToPopularQuestions
FROM
    UserEngagement ue
LEFT JOIN
    QuestionAnswerPerformance qap ON ue.UserId = qap.AnswerOwnerUserId
LEFT JOIN
    PostHistoricalMetrics phm ON ue.UserId = phm.OwnerUserId
WHERE
    ue.Reputation > 10000 -- Focus on highly established users
    AND ue.AnswersPosted > 20 -- Ensure significant answer contribution
    AND ue.LastAccessDate > NOW() - INTERVAL '3 months' -- Active users within last quarter
    AND ue.GoldBadges >= 1 -- Only users with at least one gold badge
GROUP BY
    ue.UserId, ue.DisplayName, ue.Reputation, ue.GoldBadges, ue.SilverBadges, ue.BronzeBadges,
    ue.QuestionsPosted, ue.AnswersPosted, ue.TotalAnswerScore, ue.TotalCommentsMade, ue.UserProfileViews,
    ue.TotalQuestionScore, ue.LastAccessDate, ue.TotalUpVotesGiven, ue.TotalDownVotesGiven
HAVING
    COUNT(qap.AnswerId) > 10 -- At least 10 answers considered in the performance metrics
    AND AVG(qap.TimeToAnswer_Minutes) FILTER (WHERE qap.TimeToAnswer_Minutes IS NOT NULL) < 1440 -- Average answer time less than 24 hours
ORDER BY
    InfluenceScore DESC, AvgAnswerScorePerUser DESC, ue.Reputation DESC
LIMIT 50;
