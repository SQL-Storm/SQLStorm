-- {"query": "1749.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3207} 

WITH UserBaseMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPostsContributed,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsAsked,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersProvided,
        AVG(CASE WHEN p.PostTypeId = 1 THEN p.Score ELSE NULL END) AS AvgQuestionScore,
        AVG(CASE WHEN p.PostTypeId = 2 THEN p.Score ELSE NULL END) AS AvgAnswerScore,
        SUM(CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN 1 ELSE 0 END) AS QuestionsWithAcceptedAnswer,
        SUM(CASE WHEN p.PostTypeId = 2 AND parent.AcceptedAnswerId = p.Id THEN 1 ELSE 0 END) AS AcceptedAnswersCount
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Posts parent ON p.PostTypeId = 2 AND p.ParentId = parent.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostDetailsAgg AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate,
        p.LastActivityDate,
        p.Title,
        p.Body,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        (SELECT COUNT(ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)) AS EditCount,
        EXTRACT(EPOCH FROM (p.LastEditDate - p.CreationDate)) / 86400.0 AS DaysToLastEdit,
        COALESCE(AVG(c.Score), 0.0) AS AvgCommentScore,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteCount,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteCount,
        COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC, p.ViewCount DESC, p.LastActivityDate DESC) AS UserPostRank,
        LAG(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousUserPostDate,
        LEAD(p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS NextUserPostDate
    FROM Posts p
    LEFT JOIN Comments c ON p.Id = c.PostId
    LEFT JOIN Votes v ON p.Id = v.PostId
    WHERE p.PostTypeId IN (1, 2)
    GROUP BY p.Id, p.PostTypeId, p.OwnerUserId, p.CreationDate, p.LastEditDate, p.LastActivityDate, p.Title, p.Body, p.Tags, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount
),
PostTagAnalysis AS (
    SELECT
        pda.PostId,
        pda.PostTypeId,
        pda.OwnerUserId,
        string_to_array(SUBSTRING(pda.Tags FROM 2 FOR LENGTH(pda.Tags)-2), '><') AS TagArray
    FROM PostDetailsAgg pda
    WHERE pda.Tags IS NOT NULL AND LENGTH(pda.Tags) > 2
),
ModeratorCloseEvents AS (
    SELECT
        ph.PostId,
        ph.CreationDate AS ClosureDate,
        crt.Name AS CloseReasonName,
        ph.PostHistoryTypeId,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Comment = '101' THEN 1 ELSE 0 END) AS IsDuplicateReasonNew,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Text LIKE '%OriginalQuestionIds%' THEN
            COALESCE(ARRAY_LENGTH(jsonb_array_to_text_array(ph.Text::jsonb -> 'OriginalQuestionIds'), 1), 0)
        ELSE 0 END) AS DuplicateQuestionCount,
        CASE WHEN ph.PostHistoryTypeId = 10 AND ph.Text LIKE '%OriginalQuestionIds%' THEN
            jsonb_array_to_text_array(ph.Text::jsonb -> 'OriginalQuestionIds')
        ELSE NULL END AS OriginalQuestionIds
    FROM PostHistory ph
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = crt.Id::varchar
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15)
    GROUP BY ph.PostId, ph.CreationDate, crt.Name, ph.PostHistoryTypeId, ph.Text
),
UserBadgeSummary AS (
    SELECT
        b.UserId,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadges,
        STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadgeCount,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadgeCount,
        COUNT(b.Id) FILTER (WHERE b.TagBased = TRUE) AS TagBasedBadgesCount,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
ClassifiedUsers AS (
    SELECT
        ubm.UserId,
        ubm.DisplayName,
        'High Engagement Questioner' AS UserTypeClassification,
        pda.PostId AS TopPostId,
        pda.Title AS TopPostTitle,
        pda.Score AS TopPostScore,
        pda.ViewCount AS TopPostViewCount,
        pda.AnswerCount AS TopPostAnswerCount,
        pda.EditCount AS TopPostEditCount,
        pda.DaysToLastEdit AS TopPostDaysToLastEdit,
        NULL::int AS AnswerScoreThresholdedCount,
        NULL::text AS KeyAnswerTags
    FROM UserBaseMetrics ubm
    INNER JOIN PostDetailsAgg pda ON ubm.UserId = pda.OwnerUserId
    WHERE pda.PostTypeId = 1
      AND pda.UserPostRank = 1
      AND pda.ViewCount > 50000
      AND pda.Score > 500
      AND pda.AnswerCount >= 10
      AND pda.Tags LIKE '%<sql>%' -- Specific tag pattern
    
    UNION ALL
    
    SELECT
        ubm.UserId,
        ubm.DisplayName,
        'Prolific Answerer' AS UserTypeClassification,
        pda.PostId AS TopPostId,
        pda.Title AS TopPostTitle, -- This would be the parent question's title for an answer
        pda.Score AS TopPostScore,
        pda.ViewCount AS TopPostViewCount, -- This would be the parent question's view count for an answer
        NULL AS TopPostAnswerCount, -- Not applicable for an answer post itself
        pda.EditCount AS TopPostEditCount,
        pda.DaysToLastEdit AS TopPostDaysToLastEdit,
        (
            SELECT COUNT(p_sub.Id)
            FROM Posts p_sub
            WHERE p_sub.OwnerUserId = ubm.UserId
              AND p_sub.PostTypeId = 2
              AND p_sub.Score > 100
        ) AS AnswerScoreThresholdedCount, -- Correlated subquery for answer count
        (
            SELECT STRING_AGG(DISTINCT t_sub.TagName, ', ')
            FROM PostDetailsAgg p_sub
            CROSS JOIN LATERAL UNNEST(string_to_array(SUBSTRING(p_sub.Tags FROM 2 FOR LENGTH(p_sub.Tags)-2), '><')) AS t_sub(TagName)
            WHERE p_sub.OwnerUserId = ubm.UserId
              AND p_sub.PostTypeId = 2
              AND p_sub.Score > 150
            LIMIT 5
        ) AS KeyAnswerTags -- String aggregation + substring for top answer tags
    FROM UserBaseMetrics ubm
    INNER JOIN PostDetailsAgg pda ON ubm.UserId = pda.OwnerUserId
    WHERE pda.PostTypeId = 2
      AND pda.UserPostRank = 1 -- Top answer by score
      AND pda.Score > 200
      AND ubm.AcceptedAnswersCount >= 5 -- User has at least 5 accepted answers
      AND ubm.TotalAnswersProvided > 50 -- At least 50 answers
)
SELECT
    cu.DisplayName,
    cu.UserId,
    cu.UserTypeClassification,
    ubm.Reputation,
    ubm.UserCreationDate,
    ubm.LastAccessDate,
    EXTRACT(YEAR FROM AGE(ubm.LastAccessDate, ubm.UserCreationDate)) AS YearsActive,
    ubm.TotalPostsContributed,
    ubm.TotalQuestionsAsked,
    ubm.TotalAnswersProvided,
    COALESCE(ubm.AvgQuestionScore, 0.0) AS AvgQuestionScore,
    COALESCE(ubm.AvgAnswerScore, 0.0) AS AvgAnswerScore,
    ubm.AcceptedAnswersCount,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.GoldBadgeCount,
    ubs.SilverBadgeCount,
    ubs.TagBasedBadgesCount,
    cu.TopPostId,
    cu.TopPostTitle,
    cu.TopPostScore,
    cu.TopPostViewCount,
    cu.TopPostAnswerCount,
    cu.TopPostEditCount,
    cu.TopPostDaysToLastEdit,
    cu.AnswerScoreThresholdedCount,
    cu.KeyAnswerTags,
    (
        SELECT COUNT(ph_other.UserId)
        FROM PostHistory ph_other
        WHERE ph_other.PostId = cu.TopPostId
          AND ph_other.PostHistoryTypeId IN (4, 5, 6)
          AND ph_other.UserId IS NOT NULL
          AND ph_other.UserId != ubm.UserId
    ) AS TopPostEditedByOtherUsersCount,
    MAX(CASE WHEN mce.PostId = cu.TopPostId THEN mce.CloseReasonName ELSE NULL END) AS LatestClosureReasonForTopPost,
    MAX(CASE WHEN mce.PostId = cu.TopPostId THEN mce.DuplicateQuestionCount ELSE NULL END) AS TopPostLinkedDuplicatesCount,
    STRING_AGG(DISTINCT JSONB_ARRAY_ELEMENTS_TEXT(mce.OriginalQuestionIds)::varchar, ', ') FILTER (WHERE mce.OriginalQuestionIds IS NOT NULL AND mce.PostId = cu.TopPostId) AS OriginalQuestionIDsIfDuplicate,
    SUM(pda_all.EditCount) AS TotalEditsAcrossAllPosts,
    COALESCE(NULLIF(SUM(pda_all.EditCount) / NULLIF(ubm.TotalPostsContributed, 0.0), 0.0), 0.0) AS AvgEditsPerPost,
    AVG(pda_all.DaysToLastEdit) FILTER (WHERE pda_all.PostTypeId = 1) AS AvgDaysToLastEditQuestions,
    AVG(pda_all.DaysToLastEdit) FILTER (WHERE pda_all.PostTypeId = 2) AS AvgDaysToLastEditAnswers,
    RANK() OVER (ORDER BY ubm.Reputation DESC, ubm.UserUpVotes DESC, ubm.UserProfileViews DESC, ubm.TotalPostsContributed DESC) AS GlobalUserPerformanceRank,
    NTH_VALUE(pda_all.PostCreationDate, 2) OVER (PARTITION BY ubm.UserId ORDER BY pda_all.PostCreationDate) AS SecondPostCreationDate,
    CASE
        WHEN ubm.Reputation > 20000 AND ubs.GoldBadgeCount >= 3 THEN 'Legendary Contributor'
        WHEN ubm.Reputation > 5000 AND ubs.SilverBadgeCount >= 5 THEN 'Distinguished Expert'
        WHEN ubm.TotalQuestionsAsked > 100 AND COALESCE(ubm.AvgQuestionScore, 0) > 20 THEN 'Frequent Questioner'
        WHEN ubm.TotalAnswersProvided > 200 AND COALESCE(ubm.AvgAnswerScore, 0) > 30 THEN 'Dedicated Answerer'
        ELSE 'Active Participant'
    END AS UserTierClassification,
    EXISTS (
        SELECT 1
        FROM Posts p_sub
        WHERE p_sub.OwnerUserId = ubm.UserId
          AND p_sub.CommentCount > 10
          AND p_sub.Body ILIKE '%database%'
          AND p_sub.CreationDate > (ubm.UserCreationDate + INTERVAL '1 year')
    ) AS HasMatureDiscussedPost,
    MAX(ARRAY_LENGTH(pta.TagArray, 1)) AS MaxTagsOnAS