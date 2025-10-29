-- {"query": "2111.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1996} 
WITH UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadgeCount,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
HighScorePosts AS (
    SELECT
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostRank
    FROM Posts p
    WHERE p.PostTypeId IN (1, 2) AND p.Score >= 10
),
UserPostAggregates AS (
    SELECT
        OwnerUserId,
        COUNT(*) AS HighScorePostCount,
        AVG(Score) AS AvgHighScore,
        MAX(Score) AS MaxHighScore,
        SUM(ViewCount) AS TotalViewsOnHighScorePosts,
        STRING_AGG(
            CONCAT_WS(' | ',
                COALESCE(Title, '[No Title]'),
                'Score: ' || Score,
                'Views: ' || ViewCount,
                'Created: ' || TO_CHAR(CreationDate, 'YYYY-MM-DD')
            ),
            ' || '
            ORDER BY Score DESC, ViewRank
        ) AS PostSummary
    FROM (
        SELECT 
            hsp.*,
            ROW_NUMBER() OVER (PARTITION BY OwnerUserId ORDER BY Score DESC, ViewCount DESC) AS ViewRank
        FROM HighScorePosts hsp
    ) sub
    GROUP BY OwnerUserId
),
UserLastActivity AS (
    SELECT
        p.OwnerUserId,
        MAX(p.LastActivityDate) AS LastActivity,
        COUNT(DISTINCT p.Tags) FILTER (WHERE p.PostTypeId = 1 AND p.Tags IS NOT NULL) AS DistinctTagsUsed
    FROM Posts p
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
    GROUP BY p.OwnerUserId
),
QuestionAnswerRatios AS (
    SELECT
        u.Id AS UserId,
        COALESCE(question_counts.QuestionCount,0) AS Questions,
        COALESCE(answer_counts.AnswerCount,0) AS Answers,
        CASE WHEN COALESCE(question_counts.QuestionCount,0) = 0 THEN NULL
             ELSE ROUND(CAST(COALESCE(answer_counts.AnswerCount,0) AS numeric) / question_counts.QuestionCount, 2) END AS AnswerToQuestionRatio
    FROM Users u
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS QuestionCount
        FROM Posts
        WHERE PostTypeId = 1
        GROUP BY OwnerUserId
    ) AS question_counts ON question_counts.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT OwnerUserId, COUNT(*) AS AnswerCount
        FROM Posts
        WHERE PostTypeId = 2
        GROUP BY OwnerUserId
    ) AS answer_counts ON answer_counts.OwnerUserId = u.Id
),
CloseReasonStats AS (
    SELECT
        ph.UserId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVoteCount
    FROM PostHistory ph
    JOIN CloseReasonTypes crt ON CAST(ph.Comment AS INT) = crt.Id AND ph.PostHistoryTypeId = 10
    WHERE ph.UserId IS NOT NULL
    GROUP BY ph.UserId, crt.Name
),
UserCloseVotesPivot AS (
    SELECT
        UserId,
        MAX(CASE WHEN CloseReason = 'Duplicate' THEN CloseVoteCount ELSE 0 END) AS DuplicateCloseVotes,
        MAX(CASE WHEN CloseReason = 'Off-topic' THEN CloseVoteCount ELSE 0 END) AS OffTopicCloseVotes,
        MAX(CASE WHEN CloseReason = 'Needs details or clarity' THEN CloseVoteCount ELSE 0 END) AS NeedsClarifyCloseVotes,
        MAX(CASE WHEN CloseReason = 'Needs more focus' THEN CloseVoteCount ELSE 0 END) AS NeedsFocusCloseVotes,
        MAX(CASE WHEN CloseReason = 'Opinion-based' THEN CloseVoteCount ELSE 0 END) AS OpinionBasedCloseVotes
    FROM CloseReasonStats
    GROUP BY UserId
),
UserActivitySummary AS (
    SELECT
        ub.UserId,
        ub.DisplayName,
        ub.Reputation,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadgeCount,
        uba.HighScorePostCount,
        uba.AvgHighScore,
        uba.MaxHighScore,
        uba.TotalViewsOnHighScorePosts,
        upa.PostSummary,
        ua.LastActivity,
        ua.DistinctTagsUsed,
        qar.Questions,
        qar.Answers,
        qar.AnswerToQuestionRatio,
        COALESCE(usv.DuplicateCloseVotes, 0) AS DuplicateCloseVotes,
        COALESCE(usv.OffTopicCloseVotes, 0) AS OffTopicCloseVotes,
        COALESCE(usv.NeedsClarifyCloseVotes, 0) AS NeedsClarifyCloseVotes,
        COALESCE(usv.NeedsFocusCloseVotes, 0) AS NeedsFocusCloseVotes,
        COALESCE(usv.OpinionBasedCloseVotes, 0) AS OpinionBasedCloseVotes
    FROM UserBadgeCounts ub
    LEFT JOIN UserPostAggregates uba ON uba.OwnerUserId = ub.UserId
    LEFT JOIN UserPostAggregates upa ON upa.OwnerUserId = ub.UserId
    LEFT JOIN UserLastActivity ua ON ua.OwnerUserId = ub.UserId
    LEFT JOIN QuestionAnswerRatios qar ON qar.UserId = ub.UserId
    LEFT JOIN UserCloseVotesPivot usv ON usv.UserId = ub.UserId
),
TopUserTags AS (
    SELECT DISTINCT ON (p.OwnerUserId)
        p.OwnerUserId,
        t.TagName,
        t.Count AS TagUseCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY t.Count DESC) AS TagRank
    FROM Posts p
    JOIN LATERAL (
        SELECT unnest(string_to_array(trim(both '<>' from COALESCE(p.Tags, '')), '><')) AS TagName
    ) tag_names ON TRUE
    JOIN Tags t ON t.TagName = tag_names.TagName
    WHERE p.OwnerUserId IS NOT NULL AND p.OwnerUserId <> -1
),
RankedTopTags AS (
    SELECT
        OwnerUserId,
        STRING_AGG(TagName, ', ' ORDER BY TagRank) AS TopTags
    FROM TopUserTags
    WHERE TagRank <= 3
    GROUP BY OwnerUserId
)
SELECT
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.TagBasedBadgeCount,
    COALESCE(upt.TopTags, '[No Tags]') AS TopTags,
    uas.HighScorePostCount,
    COALESCE(ROUND(uas.AvgHighScore, 2), 0) AS AvgHighScore,
    uas.MaxHighScore,
    uas.TotalViewsOnHighScorePosts,
    uas.LastActivity,
    uas.DistinctTagsUsed,
    uas.Questions,
    uas.Answers,
    COALESCE(uas.AnswerToQuestionRatio, 0) AS AnswerToQuestionRatio,
    uas.DuplicateCloseVotes,
    uas.OffTopicCloseVotes,
    uas.NeedsClarifyCloseVotes,
    uas.NeedsFocusCloseVotes,
    uas.OpinionBasedCloseVotes,
    /* Correlated subquery for latest comment text on user's highest scoring post */
    (
        SELECT c.Text
        FROM Comments c
        JOIN Posts p ON p.Id = c.PostId
        WHERE p.OwnerUserId = uas.UserId
        ORDER BY c.CreationDate DESC
        LIMIT 1
    ) AS LatestCommentOnUserPosts,
    /* Case with NULL logic and string expressions */
    CASE
        WHEN uas.Reputation >= 50000 THEN 'Legendary'
        WHEN uas.Reputation >= 10000 THEN 'Expert'
        WHEN uas.Reputation >= 1000 THEN 'Intermediate'
        ELSE 'Newbie'
    END AS UserTier,
    /* Complex expression: score-weighted badge multiplier sum */
    (uas.GoldBadges * 3 + uas.SilverBadges * 2 + uas.BronzeBadges) * NULLIF(uas.AnswerToQuestionRatio, 0) AS BadgeRepWeightedScore
FROM UserActivitySummary uas
LEFT JOIN RankedTopTags upt ON upt.OwnerUserId = uas.UserId
WHERE uas.HighScorePostCount > 5
AND uas.LastActivity > NOW() - INTERVAL '1 year'
ORDER BY uas.BadgeRepWeightedScore DESC NULLS LAST, uas.Reputation DESC
LIMIT 50;