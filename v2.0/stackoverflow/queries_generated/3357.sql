-- {"query": "3357.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1788} 

WITH RECURSIVE
/*--------------------------------------------------------------
  1.  Aggregate badge statistics per user, including class counts
--------------------------------------------------------------*/
UserBadgeStats AS (
    SELECT u.Id,
           u.DisplayName,
           COUNT(*) FILTER (WHERE b.Class = 1)   AS GoldBadges,
           COUNT(*) FILTER (WHERE b.Class = 2)   AS SilverBadges,
           COUNT(*) FILTER (WHERE b.Class = 3)   AS BronzeBadges,
           MAX(b.Date)                           AS LastBadgeDate
    FROM   Users u
    LEFT   JOIN Badges b ON b.UserId = u.Id
    GROUP  BY u.Id, u.DisplayName
),

/*--------------------------------------------------------------
  2.  Aggregate post statistics per user (questions, answers,
      total score, latest post, distinct tag list)
--------------------------------------------------------------*/
UserPostStats AS (
    SELECT p.OwnerUserId                                    AS UserId,
           COUNT(*) FILTER (WHERE p.PostTypeId = 1)        AS Questions,
           COUNT(*) FILTER (WHERE p.PostTypeId = 2)        AS Answers,
           COALESCE(SUM(p.Score),0)                       AS TotalScore,
           MAX(p.CreationDate)                            AS LastPostDate,
           STRING_AGG(DISTINCT
               CASE WHEN p.Tags IS NOT NULL
                    THEN REGEXP_REPLACE(p.Tags, '[<>]', '', 'g')
               END, ',')                                 AS TagList
    FROM   Posts p
    GROUP  BY p.OwnerUserId
),

/*--------------------------------------------------------------
  3.  Derive the most recent activity (badge or post) per user
--------------------------------------------------------------*/
UserActivity AS (
    SELECT u.Id,
           GREATEST(
               COALESCE(ubs.LastBadgeDate, TIMESTAMP '1970-01-01'),
               COALESCE(ups.LastPostDate, TIMESTAMP '1970-01-01')
           )                                            AS LastActivity
    FROM   Users u
    LEFT   JOIN UserBadgeStats ubs ON ubs.Id = u.Id
    LEFT   JOIN UserPostStats ups  ON ups.UserId = u.Id
),

/*--------------------------------------------------------------
  4.  Rank users by gold badges (desc) then total score (desc)
--------------------------------------------------------------*/
TopUsers AS (
    SELECT ua.Id,
           ua.DisplayName,
           ub.GoldBadges,
           ub.SilverBadges,
           ub.BronzeBadges,
           up.Questions,
           up.Answers,
           up.TotalScore,
           ua.LastActivity,
           ROW_NUMBER() OVER (
               ORDER BY ub.GoldBadges DESC,
                        up.TotalScore DESC,
                        ua.LastActivity DESC
           )                                            AS Rank
    FROM   Users ua
    LEFT   JOIN UserBadgeStats ub ON ub.Id = ua.Id
    LEFT   JOIN UserPostStats up ON up.UserId = ua.Id
    WHERE  ua.Reputation > 5000
      AND  (ub.GoldBadges IS NOT NULL AND ub.GoldBadges > 0)
)

/*--------------------------------------------------------------
  5.  Final result set – top 100 users with an extra correlated
      sub‑query counting distinct tags used in the last 30 days
--------------------------------------------------------------*/
SELECT tu.Id,
       tu.DisplayName,
       tu.GoldBadges,
       tu.SilverBadges,
       tu.BronzeBadges,
       tu.Questions,
       tu.Answers,
       tu.TotalScore,
       tu.LastActivity,
       tu.Rank,
       /* Correlated sub‑query: distinct tags a user used in the last 30 days */
       (
           SELECT COUNT(DISTINCT t.TagName)
           FROM   Posts p2
           CROSS  JOIN LATERAL REGEXP_SPLIT_TO_TABLE(p2.Tags, '[><]+') AS tag(tagname)
           JOIN   Tags t ON t.TagName = tag.tagname
           WHERE  p2.OwnerUserId = tu.Id
             AND  p2.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
       ) AS RecentDistinctTagCount
FROM   TopUsers tu
WHERE  tu.Rank <= 100
ORDER  BY tu.Rank;
