-- {"query": "2315.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1789} 
WITH RecentActiveUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        COALESCE(u.WebsiteUrl, '') AS WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        BadgesSummary.BadgeCount,
        BadgesSummary.GoldBadges,
        BadgesSummary.SilverBadges,
        BadgesSummary.BronzeBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS UserRank
    FROM Users u
    LEFT JOIN (
        SELECT
            b.UserId,
            COUNT(*) AS BadgeCount,
            COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
            COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
            COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges
        FROM Badges b
        GROUP BY b.UserId
    ) BadgesSummary ON BadgesSummary.UserId = u.Id
    WHERE u.LastAccessDate >= NOW() - INTERVAL '90 day'
),
TopQuestionAnswers AS (
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.AnswerCount,
        a.Id AS AnswerId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreationDate,
        a.OwnerUserId AS AnswerOwnerUserId,
        ROW_NUMBER() OVER (PARTITION BY p.Id ORDER BY a.Score DESC, a.CreationDate ASC) AS RankAnswer
    FROM Posts p
    LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
    WHERE p.PostTypeId = 1
      AND p.Score >= 10
      AND p.ViewCount >= 1000
),
FilteredTopAnswers AS (
    SELECT
        PostId,
        OwnerUserId,
        Score,
        ViewCount,
        CreationDate,
        Title,
        Tags,
        AnswerCount,
        AnswerId,
        AnswerScore,
        AnswerCreationDate,
        AnswerOwnerUserId
    FROM TopQuestionAnswers
    WHERE RankAnswer = 1
),
UserAnswerStats AS (
    SELECT
        u.Id,
        COUNT(a.Id) AS TotalAnswers,
        AVG(a.Score) AS AvgAnswerScore,
        SUM(COALESCE(vu.UpVotes,0)) AS TotalUpVotes,
        SUM(COALESCE(vd.DownVotes,0)) AS TotalDownVotes,
        MAX(a.CreationDate) AS LastAnswerDate
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    LEFT JOIN Users vu ON vu.Id = u.Id
    LEFT JOIN Users vd ON vd.Id = u.Id
    WHERE u.Id IS NOT NULL
    GROUP BY u.Id
),
QuestionsWithCloseInfo AS (
    SELECT
        p.Id,
        p.Title,
        p.CreationDate,
        p.ClosedDate,
        p.OwnerUserId,
        p.Score,
        COUNT(c.Id) FILTER (WHERE c.PostHistoryTypeId = 10) AS CloseVotesCount,
        cr.Name AS CloseReasonName,
        (SELECT COUNT(*) 
         FROM PostHistory ph2 
         WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 11) AS ReopenVotesCount
    FROM Posts p
    LEFT JOIN PostHistory c ON c.PostId = p.Id AND c.PostHistoryTypeId = 10
    LEFT JOIN CloseReasonTypes cr ON cr.Id = CAST(c.Comment AS SMALLINT)
    WHERE p.PostTypeId = 1
    GROUP BY p.Id, p.Title, p.CreationDate, p.ClosedDate, p.OwnerUserId, p.Score, cr.Name
),
UserTagActivity AS (
    SELECT 
        u.Id AS UserId,
        unnest(string_to_array(regexp_replace(p.Tags, '[<>]', '', 'g'), '')) AS TagName,
        COUNT(*) AS PostCountPerTag,
        AVG(p.Score) AS AvgScorePerTag
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id AND p.PostTypeId = 1
    GROUP BY u.Id, TagName
),
UserAnswerVotes AS (
    SELECT
        a.OwnerUserId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        COUNT(v.Id) AS TotalVotes
    FROM Posts a
    LEFT JOIN Votes v ON v.PostId = a.Id
    WHERE a.PostTypeId = 2
    GROUP BY a.OwnerUserId
),
CombinedUserStats AS (
    SELECT
        r.Id,
        r.DisplayName,
        r.Reputation,
        r.Views,
        r.UpVotes,
        r.DownVotes,
        r.BadgeCount,
        r.GoldBadges,
        r.SilverBadges,
        r.BronzeBadges,
        COALESCE(uas.TotalAnswers, 0) AS TotalAnswers,
        COALESCE(uas.AvgAnswerScore, 0) AS AvgAnswerScore,
        COALESCE(uav.UpVotes, 0) AS AnswerUpVotes,
        COALESCE(uav.DownVotes, 0) AS AnswerDownVotes,
        COALESCE(uta.PostCountPerTag, 0) AS PostsInTopTagCount,
        COALESCE(uta.AvgScorePerTag, 0) AS AvgScoreInTopTag
    FROM RecentActiveUsers r
    LEFT JOIN UserAnswerStats uas ON uas.Id = r.Id
    LEFT JOIN UserAnswerVotes uav ON uav.OwnerUserId = r.Id
    LEFT JOIN (
        SELECT UserId, PostCountPerTag, AvgScorePerTag
        FROM UserTagActivity uta1
        WHERE uta1.PostCountPerTag = (
            SELECT MAX(uta2.PostCountPerTag)
            FROM UserTagActivity uta2
            WHERE uta2.UserId = uta1.UserId
        )
        LIMIT 1
    ) uta ON uta.UserId = r.Id
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.Views,
    u.BadgeCount,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    u.TotalAnswers,
    u.AvgAnswerScore,
    u.AnswerUpVotes,
    u.AnswerDownVotes,
    u.PostsInTopTagCount,
    u.AvgScoreInTopTag,
    ARRAY_AGG(DISTINCT t.TagName) AS UserTopTags,
    sq.Title AS TopQuestionTitle,
    sq.Score AS TopQuestionScore,
    sq.ViewCount AS TopQuestionViews,
    sq.AnswerScore AS TopAnswerScore,
    CASE WHEN qwi.ClosedDate IS NOT NULL THEN TRUE ELSE FALSE END AS IsQuestionClosed,
    qwi.CloseVotesCount,
    qwi.CloseReasonName,
    qwi.ReopenVotesCount,
    CONCAT(
        COALESCE(sq.Tags, ''), ' | ',
        COALESCE(t.TagName, ''), ' | ',
        COALESCE(u.Location, 'Unknown'), ' | ',
        COALESCE(u.WebsiteUrl, 'No URL')
    ) AS UserTagLocationWebsiteInfo,
    RANK() OVER (ORDER BY u.Reputation DESC, u.Views DESC) AS GlobalUserRank
FROM CombinedUserStats u
LEFT JOIN FilteredTopAnswers sq ON sq.OwnerUserId = u.Id
LEFT JOIN QuestionsWithCloseInfo qwi ON qwi.Id = sq.PostId
LEFT JOIN LATERAL (
    SELECT DISTINCT UNNEST(string_to_array(regexp_replace(u.DisplayName, '[^a-zA-Z0-9 ]', '', 'g'), ' ')) AS TagName
) t ON TRUE
WHERE u.TotalAnswers > 10
  AND (sq.Score > 50 OR u.GoldBadges > 0)
  AND (
    u.PostsInTopTagCount > 5
    OR u.BadgeCount > 10
    OR u.AnswerUpVotes > u.AnswerDownVotes * 2
  )
ORDER BY u.Reputation DESC, u.Views DESC
LIMIT 100;