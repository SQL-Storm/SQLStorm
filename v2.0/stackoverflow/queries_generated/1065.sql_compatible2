WITH RecentActiveUsers AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS HasGoldBadge,
        SUBSTRING(u.Location FROM 1 FOR 50) AS UserLocationPrefix
    FROM Users u
    LEFT JOIN Badges b ON u.Id = b.UserId
    WHERE u.LastAccessDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '2 years')
      AND u.Reputation >= 1000
      AND u.DisplayName IS NOT NULL
      AND u.AboutMe IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
        u.UpVotes, u.DownVotes, u.Views, u.Location
    HAVING COUNT(DISTINCT b.Id) > 0
),
QuestionDetails AS (
    SELECT
        q.Id AS QuestionId,
        q.OwnerUserId,
        q.Title,
        q.CreationDate AS QuestionCreationDate,
        q.Score AS QuestionScore,
        q.ViewCount AS QuestionViewCount,
        q.AnswerCount,
        q.CommentCount AS QuestionCommentCount,
        q.FavoriteCount,
        q.AcceptedAnswerId,
        STRING_AGG(DISTINCT t.TagName, ',') AS RelatedTags,
        MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE 0 END) AS WasClosed,
        MAX(CASE WHEN ph.PostHistoryTypeId = 52 THEN 1 ELSE 0 END) AS WasHotQuestion,
        MAX(ph.CreationDate) AS LastPostActivityDate,
        SUM(COALESCE(c.Score, 0)) AS TotalCommentScoreOnQuestion,
        COUNT(c.Id) AS TotalCommentsOnQuestion,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.CreationDate DESC, q.Score DESC) AS rn_user_question_creation,
        AVG(q.Score) OVER (PARTITION BY q.OwnerUserId) AS AvgQuestionScoreByUser
    FROM Posts q
    JOIN PostTypes pt ON q.PostTypeId = pt.Id
    LEFT JOIN PostHistory ph ON q.Id = ph.PostId AND ph.PostHistoryTypeId IN (10, 52)
    LEFT JOIN Comments c ON q.Id = c.PostId
    LEFT JOIN (
        SELECT p_inner.Id, unnest(string_to_array(SUBSTRING(p_inner.Tags FROM 2 FOR CHAR_LENGTH(p_inner.Tags) - 2), '><')) AS TagName
        FROM Posts p_inner
        WHERE p_inner.PostTypeId = 1 AND p_inner.Tags IS NOT NULL AND CHAR_LENGTH(p_inner.Tags) > 2
    ) AS q_tags ON q.Id = q_tags.Id
    LEFT JOIN Tags t ON q_tags.TagName = t.TagName
    WHERE q.PostTypeId = 1
      AND q.OwnerUserId IS NOT NULL
      AND q.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years')
    GROUP BY
        q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount,
        q.AnswerCount, q.CommentCount, q.FavoriteCount, q.AcceptedAnswerId
    HAVING COUNT(DISTINCT t.TagName) > 0
),
AnswerEngagement AS (
    SELECT
        a.OwnerUserId AS AnswererId,
        a.ParentId AS QuestionId,
        COUNT(a.Id) AS TotalAnswersByThisUserForQuestion,
        SUM(a.Score) AS TotalAnswerScoreByThisUserForQuestion,
        MAX(CASE WHEN a.Id = qd.AcceptedAnswerId THEN 1 ELSE 0 END) AS WasAcceptedAnswer,
        (
            SELECT COUNT(DISTINCT co.Id)
            FROM Comments co
            WHERE co.PostId = a.Id
              AND co.Score >= 5
              AND co.CreationDate > a.CreationDate
        ) AS HighScoreCommentsOnAnswer
    FROM Posts a
    JOIN QuestionDetails qd ON a.ParentId = qd.QuestionId
    WHERE a.PostTypeId = 2
      AND a.OwnerUserId IS NOT NULL
      AND a.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years')
    GROUP BY
        a.OwnerUserId, a.ParentId, qd.AcceptedAnswerId, a.Id, a.CreationDate
),
PostLinkAggregates AS (
    SELECT
        pl.PostId,
        COUNT(pl.RelatedPostId) AS TotalLinkedPosts,
        SUM(CASE WHEN pl.LinkTypeId = 3 THEN 1 ELSE 0 END) AS TotalDuplicateLinks,
        ARRAY_AGG(DISTINCT lt.Name) FILTER (WHERE lt.Name IS NOT NULL) AS LinkTypeNames
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '5 years')
    GROUP BY pl.PostId
),
UserPostAggregates AS (
    SELECT
        rau.UserId,
        rau.DisplayName,
        rau.Reputation,
        rau.TotalBadges,
        rau.HasGoldBadge,
        rau.UserProfileViews,
        rau.UserLocationPrefix,
        COUNT(DISTINCT qd.QuestionId) AS TotalQuestionsPosted,
        SUM(COALESCE(qd.QuestionScore, 0)) AS TotalQuestionScore,
        SUM(COALESCE(qd.QuestionViewCount, 0)) AS TotalQuestionViews,
        SUM(COALESCE(qd.TotalCommentScoreOnQuestion, 0)) AS TotalCommentsScoreOnUserQuestions,
        COUNT(DISTINCT ae.QuestionId) AS TotalQuestionsAnswered,
        SUM(COALESCE(ae.TotalAnswersByThisUserForQuestion, 0)) AS TotalAnswersPosted,
        SUM(COALESCE(ae.TotalAnswerScoreByThisUserForQuestion, 0)) AS TotalAnswerScore,
        SUM(CASE WHEN ae.WasAcceptedAnswer = 1 THEN 1 ELSE 0 END) AS TotalAcceptedAnswers,
        SUM(COALESCE(pla.TotalLinkedPosts, 0)) AS TotalLinkedPostsFromUserPosts,
        SUM(COALESCE(pla.TotalDuplicateLinks, 0)) AS TotalDuplicateLinksFromUserPosts,
        MAX(COALESCE(qd.WasHotQuestion, 0)) AS HasPostedHotQuestion,
        AVG(COALESCE(qd.AvgQuestionScoreByUser, 0)) AS AverageQuestionScoreOverUserLife,
        COALESCE(CAST(SUM(CASE WHEN qd.WasClosed = 1 THEN 1 ELSE 0 END) AS NUMERIC) * 100.0 / NULLIF(COUNT(DISTINCT qd.QuestionId), 0), 0) AS PercentageQuestionsClosed,
        MAX(COALESCE(ae.TotalAnswerScoreByThisUserForQuestion, 0)) AS MaxAnswerScoreForUser,
        AVG(COALESCE(ae.HighScoreCommentsOnAnswer, 0)) AS AvgHighScoreCommentsOnAnswers
    FROM RecentActiveUsers rau
    LEFT JOIN QuestionDetails qd ON rau.UserId = qd.OwnerUserId
    LEFT JOIN AnswerEngagement ae ON rau.UserId = ae.AnswererId
    LEFT JOIN PostLinkAggregates pla ON qd.QuestionId = pla.PostId OR ae.QuestionId = pla.PostId
    GROUP BY
        rau.UserId, rau.DisplayName, rau.Reputation, rau.TotalBadges, rau.HasGoldBadge,
        rau.UserProfileViews, rau.UserLocationPrefix
    HAVING COUNT(DISTINCT qd.QuestionId) > 0 OR SUM(COALESCE(ae.TotalAnswersByThisUserForQuestion, 0)) > 0
)
SELECT
    upa.UserId,
    upa.DisplayName,
    upa.Reputation,
    upa.TotalBadges,
    upa.HasGoldBadge,
    upa.UserProfileViews,
    upa.TotalQuestionsPosted,
    upa.TotalAnswersPosted,
    upa.TotalAcceptedAnswers,
    upa.TotalQuestionScore,
    upa.TotalAnswerScore,
    upa.TotalLinkedPostsFromUserPosts,
    upa.TotalDuplicateLinksFromUserPosts,
    upa.HasPostedHotQuestion,
    upa.PercentageQuestionsClosed,
    upa.MaxAnswerScoreForUser,
    upa.UserLocationPrefix,
    (
        (upa.Reputation * 0.1) +
        (upa.TotalAcceptedAnswers * 50) +
        (COALESCE(upa.TotalQuestionScore, 0) * 0.5) +
        (COALESCE(upa.TotalAnswerScore, 0) * 0.7) +
        (upa.TotalBadges * 10) +
        (upa.TotalLinkedPostsFromUserPosts * 5) +
        (upa.UserProfileViews * 0.01) -
        (upa.TotalDuplicateLinksFromUserPosts * 20) -
        (upa.PercentageQuestionsClosed * 0.5)
    ) AS UserInfluenceScore,
    RANK() OVER (ORDER BY (
        (upa.Reputation * 0.1) +
        (upa.TotalAcceptedAnswers * 50) +
        (COALESCE(upa.TotalQuestionScore, 0) * 0.5) +
        (COALESCE(upa.TotalAnswerScore, 0) * 0.7) +
        (upa.TotalBadges * 10) +
        (upa.TotalLinkedPostsFromUserPosts * 5) +
        (upa.UserProfileViews * 0.01) -
        (upa.TotalDuplicateLinksFromUserPosts * 20) -
        (upa.PercentageQuestionsClosed * 0.5)
    ) DESC) AS OverallInfluenceRank,
    (
        SELECT COUNT(co.Id)
        FROM Comments co
        WHERE co.UserId = upa.UserId
          AND co.CreationDate >= (CAST('2024-10-01 12:34:56' AS TIMESTAMP) - INTERVAL '1 year')
          AND CHAR_LENGTH(co.Text) > 50
          AND co.Score > 1
    ) AS RecentSubstantialCommentsCount,
    (
        SELECT q_tags.TagName
        FROM QuestionDetails qd_sub
        LEFT JOIN (
            SELECT p_tags.Id, unnest(string_to_array(SUBSTRING(p_tags.Tags FROM 2 FOR CHAR_LENGTH(p_tags.Tags) - 2), '><')) AS TagName
            FROM Posts p_tags WHERE p_tags.PostTypeId = 1 AND p_tags.Tags IS NOT NULL AND CHAR_LENGTH(p_tags.Tags) > 2
        ) AS q_tags ON qd_sub.QuestionId = q_tags.Id
        WHERE qd_sub.OwnerUserId = upa.UserId
          AND q_tags.TagName IS NOT NULL
        ORDER BY qd_sub.QuestionViewCount DESC, qd_sub.QuestionCreationDate DESC
        LIMIT 1
    ) AS TopViewedQuestionTagSample,
    COALESCE(upa.DisplayName, 'Anonymous User') || ' (' || COALESCE(upa.UserLocationPrefix, 'Unknown Location') || ')' AS UserDisplayInfo,
    CASE
        WHEN upa.HasGoldBadge = 1 AND upa.Reputation > 75000 THEN 'Legendary Contributor'
        WHEN upa.HasGoldBadge = 1 OR upa.Reputation > 25000 THEN 'Distinguished Contributor'
        WHEN upa.TotalAcceptedAnswers > 50 AND upa.TotalAnswersPosted > 100 THEN 'Prolific Answerer'
        WHEN upa.TotalQuestionsPosted > 20 AND upa.TotalQuestionScore > 500 THEN 'Engaged Questioner'
        ELSE 'Active Contributor'
    END AS UserStatusLabel,
    upa.AvgHighScoreCommentsOnAnswers
FROM UserPostAggregates upa
WHERE (upa.TotalQuestionsPosted > 5 OR upa.TotalAnswersPosted > 10)
  AND upa.PercentageQuestionsClosed < 75
  AND (upa.AvgHighScoreCommentsOnAnswers IS NULL OR upa.AvgHighScoreCommentsOnAnswers > 0)
  AND (upa.HasPostedHotQuestion = 1 OR upa.TotalAcceptedAnswers > 20)
ORDER BY UserInfluenceScore DESC, upa.Reputation DESC, RecentSubstantialCommentsCount DESC
LIMIT 100;