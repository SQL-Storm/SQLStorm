-- {"query": "25030.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2419} 

WITH user_activity AS (
   SELECT u.Id AS UserId,
          u.DisplayName,
          u.Reputation,
          COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
          COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
          SUM(p.Score) FILTER (WHERE p.PostTypeId = 1) AS QuestionScoreSum,
          SUM(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AnswerScoreSum,
          COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 2) AS UpVoteGiven,
          COUNT(v.Id) FILTER (WHERE v.VoteTypeId = 3) AS DownVoteGiven,
          MAX(p.CreationDate) AS LastPostDate
   FROM Users u
   LEFT JOIN Posts p ON p.OwnerUserId = u.Id
   LEFT JOIN Votes v ON v.UserId = u.Id
   GROUP BY u.Id, u.DisplayName, u.Reputation
),
top_tags AS (
   SELECT t.TagName,
          t.Count AS TagUseCount,
          ROW_NUMBER() OVER (ORDER BY t.Count DESC) AS TagRank
   FROM Tags t
   WHERE t.IsModeratorOnly = 0
),
user_tag_overlap AS (
   SELECT ua.UserId,
          tt.TagName,
          COALESCE((
            SELECT COUNT(*)
            FROM Posts p
            WHERE p.OwnerUserId = ua.UserId
              AND p.Tags LIKE '%'||tt.TagName||'%'
          ), 0) AS PostsWithTag
   FROM user_activity ua
   CROSS JOIN top_tags tt
   WHERE tt.TagRank <= 5
),
recent_closed_questions AS (
   SELECT p.Id,
          p.Title,
          ph.CreationDate AS ClosedDate,
          ph.Comment AS CloseReasonJson,
          ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY ph.CreationDate DESC) AS rn,
          p.OwnerUserId
   FROM Posts p
   JOIN PostHistory ph ON ph.PostId = p.Id AND ph.PostHistoryTypeId = 10
   WHERE p.PostTypeId = 1
),
user_badge_summary AS (
   SELECT b.UserId,
          COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
          COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
          COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
          STRING_AGG(DISTINCT b.Name, ', ') FILTER (WHERE b.Class = 1) AS GoldBadgeNames
   FROM Badges b
   GROUP BY b.UserId
)
SELECT
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.QuestionScoreSum,
    ua.AnswerScoreSum,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.GoldBadgeNames,
    COALESCE(rcq.Title, 'No recent closures') AS RecentClosedTitle,
    rcq.ClosedDate,
    CASE
        WHEN rcq.CloseReasonJson IS NOT NULL THEN
            COALESCE(NULLIF(regexp_replace(rcq.CloseReasonJson, '^\s+|\s+$', ''), ''), 'Unknown')
        ELSE 'N/A'
    END AS CloseReason,
    ROUND(
        (ua.QuestionScoreSum + ua.AnswerScoreSum)::numeric /
        NULLIF((ua.QuestionCount + ua.AnswerCount), 0), 2) AS AvgScorePerPost,
    CONCAT('Top Tags: ',
           STRING_AGG(ut.TagName || '(' || ut.PostsWithTag || ')', ', ' ORDER BY ut.PostsWithTag DESC)
    ) AS TagActivity
FROM user_activity ua
LEFT JOIN user_badge_summary ub ON ub.UserId = ua.UserId
LEFT JOIN LATERAL (
    SELECT rc.Title, rc.ClosedDate, rc.CloseReasonJson
    FROM recent_closed_questions rc
    WHERE rc.OwnerUserId = ua.UserId AND rc.rn = 1
    LIMIT 1
) rcq ON TRUE
LEFT JOIN user_tag_overlap ut ON ut.UserId = ua.UserId
WHERE ua.Reputation > 1000
GROUP BY
    ua.UserId, ua.DisplayName, ua.Reputation,
    ua.QuestionCount, ua.AnswerCount,
    ua.QuestionScoreSum, ua.AnswerScoreSum,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges,
    ub.GoldBadgeNames,
    rcq.Title, rcq.ClosedDate, rcq.CloseReasonJson
HAVING COUNT(ut.TagName) > 0

UNION ALL

SELECT
    NULL AS UserId,
    'Aggregate Summary' AS DisplayName,
    NULL AS Reputation,
    SUM(ua.QuestionCount) AS QuestionCount,
    SUM(ua.AnswerCount) AS AnswerCount,
    SUM(ua.QuestionScoreSum) AS QuestionScoreSum,
    SUM(ua.AnswerScoreSum) AS AnswerScoreSum,
    NULL, NULL, NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL
FROM user_activity ua
WHERE ua.Reputation > 1000;
