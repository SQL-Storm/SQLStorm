-- {"query": "1650.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3700} 
WITH TopActiveTags AS (
    -- Identify the top 20 most viewed and active tags within the last 5 years.
    SELECT
        t.TagName,
        SUM(p.ViewCount) AS TotalTagViewCount,
        COUNT(p.Id) AS TotalTagQuestionCount
    FROM Tags t
    JOIN Posts p ON p.PostTypeId = 1 AND p.Tags LIKE '%' || t.TagName || '%'
    WHERE p.CreationDate >= NOW() - INTERVAL '5 year'
      AND p.Tags IS NOT NULL
      AND LENGTH(TRIM(REPLACE(REPLACE(p.Tags, '><', ' '), '<', ''), '>')) > 0 -- Ensure tags are not empty/malformed
    GROUP BY t.TagName
    HAVING COUNT(p.Id) >= 50
    ORDER BY TotalTagViewCount DESC, TotalTagQuestionCount DESC
    LIMIT 20
),
RecentHighImpactQuestions AS (
    -- Select questions that are from the top active tags, have significant views, and recent activity.
    SELECT
        p.Id AS PostId,
        p.Title,
        p.Body,
        p.OwnerUserId,
        p.OwnerDisplayName,
        p.CreationDate AS QuestionCreationDate,
        p.Score AS QuestionScore,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        p.ClosedDate,
        -- Extract the first tag for primary classification, handling potential NULLs or empty tags.
        COALESCE(
            SUBSTRING(p.Tags, POSITION('<' IN p.Tags) + 1, POSITION('>' IN p.Tags) - POSITION('<' IN p.Tags) - 1),
            'Untagged'
        ) AS PrimaryTag,
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.AcceptedAnswerId IS NOT NULL THEN 'AcceptedAnswered'
            WHEN p.AnswerCount > 0 THEN 'Answered'
            ELSE 'Open'
        END AS QuestionStatus
    FROM Posts p
    JOIN TopActiveTags tat ON p.Tags LIKE '%' || tat.TagName || '%'
    WHERE p.PostTypeId = 1 -- Only questions
      AND p.ViewCount > 500
      AND p.Score > 5
      AND p.CreationDate >= NOW() - INTERVAL '3 year'
      AND p.OwnerUserId IS NOT NULL
      AND p.Title IS NOT NULL
),
UserActivityBase AS (
    -- Identify a base set of users for further analysis: owners of high-impact questions and highly reputable users.
    SELECT u.Id AS UserId, u.DisplayName, u.Reputation, u.CreationDate, u.Views, u.UpVotes, u.DownVotes
    FROM Users u
    WHERE u.Id IN (SELECT DISTINCT OwnerUserId FROM RecentHighImpactQuestions WHERE OwnerUserId IS NOT NULL)
       OR u.Reputation > 20000 -- Include very high-rep users regardless of recent post activity
),
DetailedPostEditHistory AS (
    -- Trace the detailed edit history for high-impact questions to analyze edit patterns.
    SELECT
        ph.PostId,
        ph.CreationDate AS EditDate,
        ph.UserId AS EditorUserId,
        ph.PostHistoryTypeId,
        -- Calculate the sequence number for edits for each post.
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS EditSequence,
        -- Get the previous edit date for calculating time differences between edits.
        LAG(ph.CreationDate, 1, ph.CreationDate) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousEventDate
    FROM PostHistory ph
    WHERE ph.PostId IN (SELECT PostId FROM RecentHighImpactQuestions)
      AND ph.PostHistoryTypeId IN (4, 5, 6) -- Only considering 'Edit Title', 'Edit Body', 'Edit Tags'
),
PostAggregatedMetrics AS (
    -- Aggregate various metrics for each high-impact question, including historical and comment data.
    SELECT
        rhq.PostId,
        rhq.Title,
        rhq.OwnerUserId,
        rhq.QuestionCreationDate,
        rhq.QuestionScore,
        rhq.ViewCount,
        rhq.AnswerCount,
        rhq.FavoriteCount,
        rhq.LastActivityDate,
        rhq.ClosedDate,
        rhq.PrimaryTag,
        rhq.QuestionStatus,
        -- Count unique users who have edited the post.
        (SELECT COUNT(DISTINCT deph.EditorUserId) FROM DetailedPostEditHistory deph WHERE deph.PostId = rhq.PostId) AS UniqueEditorsCount,
        -- Calculate the average time (in seconds) between consecutive edits.
        COALESCE(AVG(EXTRACT(EPOCH FROM (deph.EditDate - deph.PreviousEventDate))) FILTER (WHERE deph.EditSequence > 1), 0.0) AS AvgSecondsBetweenEdits,
        -- Calculate the average score of all comments on the post.
        COALESCE((SELECT AVG(c.Score) FROM Comments c WHERE c.PostId = rhq.PostId), 0.0) AS AvgCommentScore,
        -- Count various moderation-related actions (close, reopen, lock, delete, protect).
        SUM(CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN 1 ELSE 0 END) AS ModeratorActionCount,
        -- Flag if the post was ever community-owned.
        MAX(CASE WHEN ph.PostHistoryTypeId = 16 THEN 1 ELSE 0 END) AS WasCommunityOwnedFlag,
        -- Flag if the post was closed specifically as a duplicate.
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 1 ELSE 0 END) AS ClosedAsDuplicateFlag,
        -- Calculate the time interval from question creation to its very first edit.
        MIN(deph.EditDate - rhq.QuestionCreationDate) AS TimeToFirstEditInterval
    FROM RecentHighImpactQuestions rhq
    LEFT JOIN PostHistory ph ON rhq.PostId = ph.PostId -- For moderation events
    LEFT JOIN DetailedPostEditHistory deph ON rhq.PostId = deph.PostId
    GROUP BY
        rhq.PostId, rhq.Title, rhq.OwnerUserId, rhq.QuestionCreationDate, rhq.QuestionScore,
        rhq.ViewCount, rhq.AnswerCount, rhq.FavoriteCount, rhq.LastActivityDate, rhq.ClosedDate,
        rhq.PrimaryTag, rhq.QuestionStatus
),
CombinedUserTopPosts AS (
    -- Combine high-scoring questions and answers from users in the UserActivityBase.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        'Question' AS PostType
    FROM Posts p
    WHERE p.PostTypeId = 1 AND p.Score > 50 AND p.OwnerUserId IN (SELECT UserId FROM UserActivityBase)
    UNION ALL
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        'Answer' AS PostType
    FROM Posts p
    WHERE p.PostTypeId = 2 AND p.Score > 75 AND p.OwnerUserId IN (SELECT UserId FROM UserActivityBase)
),
UserOverallEngagement AS (
    -- Summarize user engagement, badge counts, and contributions to high-scoring posts.
    SELECT
        uab.UserId,
        uab.DisplayName,
        uab.Reputation,
        uab.CreationDate AS UserJoinDate,
        uab.Views AS UserProfileViews,
        uab.UpVotes AS UserUpVotesGiven,
        uab.DownVotes AS UserDownVotesGiven,
        -- Count gold, silver, and bronze badges using conditional aggregation and COALESCE for users with no badges of a class.
        COALESCE(SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END), 0) AS GoldBadges,
        COALESCE(SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END), 0) AS SilverBadges,
        COALESCE(SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END), 0) AS BronzeBadges,
        -- Flag if the user has a specific 'Disciplined' badge, indicating consistency.
        MAX(CASE WHEN b.Name = 'Disciplined' THEN 1 ELSE 0 END) AS HasDisciplinedBadge,
        -- Count total high-scoring questions/answers from the CombinedUserTopPosts CTE.
        COUNT(DISTINCT ctp.PostId) AS TotalHighScorePosts,
        -- Average score of the user's high-scoring posts.
        COALESCE(AVG(ctp.Score), 0.0) AS AvgHighScorePostScore,
        -- Calculate the average post score for all questions owned by this user (not just high-impact ones).
        COALESCE(AVG(p_all.Score) FILTER (WHERE p_all.PostTypeId = 1), 0.0) AS OverallAvgQuestionScore,
        -- Correlated subquery: check if the user has posted any content containing a specific keyword in the last year.
        (SELECT CASE WHEN EXISTS (SELECT 1 FROM Posts p_kw WHERE p_kw.OwnerUserId = uab.UserId AND p_kw.CreationDate > NOW() - INTERVAL '1 year' AND p_kw.Body ILIKE '%kubernetes%') THEN TRUE ELSE FALSE END) AS PostedAboutKubernetesRecently
    FROM UserActivityBase uab
    LEFT JOIN Badges b ON uab.UserId = b.UserId
    LEFT JOIN CombinedUserTopPosts ctp ON uab.UserId = ctp.OwnerUserId
    LEFT JOIN Posts p_all ON uab.UserId = p_all.OwnerUserId
    GROUP BY uab.UserId, uab.DisplayName, uab.Reputation, uab.CreationDate, uab.Views, uab.UpVotes, uab.DownVotes
),
RankedUserPerformance AS (
    -- Rank users based on various performance indicators and contribution metrics.
    SELECT
        uoe.UserId,
        uoe.DisplayName,
        uoe.Reputation,
        uoe.GoldBadges,
        uoe.SilverBadges,
        uoe.BronzeBadges,
        uoe.HasDisciplinedBadge,
        uoe.TotalHighScorePosts,
        uoe.AvgHighScorePostScore,
        uoe.OverallAvgQuestionScore,
        uoe.PostedAboutKubernetesRecently,
        -- Overall rank based on reputation and high-score post count.
        RANK() OVER (ORDER BY uoe.Reputation DESC, uoe.TotalHighScorePosts DESC) AS UserOverallRank,
        -- Divide users into 4 quartiles based on their reputation.
        NTILE(4) OVER (ORDER BY uoe.Reputation DESC) AS ReputationQuartile,
        -- Average profile views for users within the same 'Disciplined Badge' group.
        AVG(uoe.UserProfileViews) OVER (PARTITION BY uoe.HasDisciplinedBadge) AS AvgViewsForDisciplineGroup,
        -- Determine expertise level based on badge counts and reputation.
        CASE
            WHEN uoe.GoldBadges >= 5 AND uoe.Reputation >= 100000 THEN 'Legendary Expert'
            WHEN uoe.GoldBadges >= 1 OR uoe.Reputation >= 50000 THEN 'Senior Expert'
            WHEN uoe.SilverBadges >= 5 OR uoe.Reputation >= 10000 THEN 'Mid-Level Contributor'
            ELSE 'Junior Contributor'
        END AS UserExpertiseLevel
    FROM UserOverallEngagement uoe
)
-- Final result set: detailed analysis of high-impact questions and their owners.
SELECT
    rup.DisplayName AS OwnerName,
    rup.Reputation AS OwnerReputation,
    rup.UserExpertiseLevel,
    rup.UserOverallRank,
    rup.ReputationQuartile,
    rup.HasDisciplinedBadge,
    rup.PostedAboutKubernetesRecently,
    pam.PostId AS QuestionID,
    pam.Title AS QuestionTitle,
    pam.QuestionCreationDate,
    pam.QuestionStatus,
    pam.PrimaryTag,
    pam.ViewCount,
    pam.QuestionScore,
    pam.AnswerCount,
    pam.FavoriteCount,
    pam.UniqueEditorsCount,
    pam.AvgCommentScore,
    pam.ModeratorActionCount,
    pam.WasCommunityOwnedFlag,
    pam.ClosedAsDuplicateFlag,
    pam.AvgSecondsBetweenEdits,
    pam.TimeToFirstEditInterval,
    -- Complex calculated metrics for post quality and engagement.
    CAST(pam.QuestionScore AS DECIMAL) / NULLIF(pam.ViewCount, 0) AS ScorePerViewRatio,
    (pam.AnswerCount * 0.75 + pam.FavoriteCount * 1.5 + pam.UniqueEditorsCount * 0.5 + pam.AvgCommentScore * 0.25) AS WeightedEngagementIndex,
    -- String manipulations and conditional classifications.
    COALESCE(UPPER(SUBSTRING(pam.Title, 1, 1)), '#') AS FirstCharOfTitle,
    TRIM(BOTH '>' FROM TRIM(BOTH '<' FROM pam.PrimaryTag)) AS CleanPrimaryTag,
    CASE
        WHEN pam.Title ILIKE '%error%' OR pam.Body ILIKE '%bug%' THEN 'Issue/Bug Report'
        WHEN pam.Title ILIKE '%how to%' OR pam.Title ILIKE '%guide%' THEN 'How-To/Guidance'
        WHEN pam.PrimaryTag IN ('javascript', 'python', 'java') THEN 'Popular Language'
        ELSE 'Other Technical'
    END AS ContentTopicCategory,
    -- Correlated subquery to retrieve the text of the top-scoring recent comment, if any.
    (
        SELECT COALESCE(STRING_AGG(c.Text, ' || ') FILTER (WHERE c.Text IS NOT NULL), 'No high-score comments recently')
        FROM Comments c
        WHERE c.PostId = pam.PostId
          AND c.CreationDate > NOW() - INTERVAL '6 month'
        ORDER BY c.Score DESC, c.CreationDate DESC
        LIMIT 1
    ) AS TopRecentCommentSnippet,
    -- Outer joins with PostLinks to find related and duplicate posts.
    pl_linked.RelatedPostId AS LinkedToPostId,
    pl_duplicate.RelatedPostId AS DuplicateOfPostId,
    -- Calculate the ratio of owner's overall average question score to this specific question's score.
    COALESCE(CAST(rup.OverallAvgQuestionScore AS DECIMAL) / NULLIF(pam.QuestionScore, 0), 0.0) AS OwnerAvgVsPostScoreRatio
FROM PostAggregatedMetrics pam
LEFT JOIN RankedUserPerformance rup ON pam.OwnerUserId = rup.UserId
LEFT JOIN PostLinks pl_linked ON pam.PostId = pl_linked.PostId AND pl_linked.LinkTypeId = 1 -- LinkType 1: Linked
LEFT JOIN PostLinks pl_duplicate ON pam.PostId = pl_duplicate.PostId AND pl_duplicate.LinkTypeId = 3 -- LinkType 3: Duplicate
WHERE
    pam.QuestionScore > 20
    AND pam.ViewCount > 10000
    AND pam.ModeratorActionCount > 0
    AND pam.ClosedAsDuplicateFlag = 1 -- Focus on moderated duplicate questions
    AND rup.ReputationQuartile = 1 -- Only questions from top 25% reputable users
    AND (pam.AvgSecondsBetweenEdits IS NULL OR pam.AvgSecondsBetweenEdits > 7200) -- Only if no edits or slow edits (avg > 2 hours)
ORDER BY
    rup.Reputation DESC NULLS LAST,
    pam.ViewCount DESC,
    pam.QuestionScore DESC,
    pam.LastActivityDate DESC
LIMIT 750;