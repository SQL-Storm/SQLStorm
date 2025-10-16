WITH UserBadgeAgg AS (
    SELECT u.Id AS UserId,
           SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
           SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
           SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
           COUNT(b.Id)                              AS TotalBadges
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id
),
UserPostAgg AS (
    SELECT u.Id AS UserId,
           COUNT(p.Id)                                            AS TotalPosts,
           SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END)      AS QuestionCount,
           SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END)      AS AnswerCount,
           AVG(p.Score)                                           AS AvgPostScore,
           MAX(p.CreationDate)                                   AS LatestPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    GROUP BY u.Id
),
UserVoteAgg AS (
    SELECT u.Id AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotesReceived,
           SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoritesReceived
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY u.Id
),
UserAnswerStats AS (
    SELECT u.Id AS UserId,
           COUNT(a.Id) FILTER (WHERE a.Id IS NOT NULL AND a.AcceptedAnswerId IS NOT NULL) AS AcceptedAnswers,
           COUNT(a.Id)                                                          AS TotalAnswers,
           CASE
               WHEN COUNT(a.Id) = 0 THEN NULL
               ELSE ROUND(100.0 *
                     COUNT(a.Id) FILTER (WHERE a.AcceptedAnswerId IS NOT NULL) /
                     NULLIF(COUNT(a.Id),0), 2)
           END AS AcceptanceRatePct
    FROM Users u
    LEFT JOIN Posts a ON a.OwnerUserId = u.Id AND a.PostTypeId = 2
    GROUP BY u.Id
),
UserTagStats AS (
    -- Move the set-returning UNNEST into a lateral subquery to allow aggregation
    SELECT u.Id AS UserId,
           COUNT(DISTINCT tag) AS DistinctTagCount
    FROM Users u
    LEFT JOIN LATERAL (
        SELECT unnest(string_to_array(TRIM(BOTH '<>' FROM p.Tags), '><')) AS tag
        FROM Posts p
        WHERE p.OwnerUserId = u.Id
          AND p.PostTypeId = 1
          AND p.Tags IS NOT NULL
    ) t ON TRUE
    GROUP BY u.Id
),
Combined AS (
    SELECT u.Id,
           u.DisplayName,
           u.Reputation,
           COALESCE(b.GoldBadges,0)          AS GoldBadges,
           COALESCE(b.SilverBadges,0)        AS SilverBadges,
           COALESCE(b.BronzeBadges,0)        AS BronzeBadges,
           COALESCE(p.TotalPosts,0)          AS TotalPosts,
           COALESCE(p.QuestionCount,0)       AS QuestionCount,
           COALESCE(p.AnswerCount,0)         AS AnswerCount,
           COALESCE(p.AvgPostScore,0)        AS AvgPostScore,
           COALESCE(v.UpVotesReceived,0)     AS UpVotesReceived,
           COALESCE(v.DownVotesReceived,0)   AS DownVotesReceived,
           COALESCE(a.AcceptedAnswers,0)     AS AcceptedAnswers,
           COALESCE(a.AcceptanceRatePct,0)   AS AcceptanceRatePct,
           COALESCE(t.DistinctTagCount,0)    AS DistinctTagCount,
           ROW_NUMBER() OVER (ORDER BY u.Reputation DESC,
                                         COALESCE(b.GoldBadges,0) DESC,
                                         COALESCE(b.SilverBadges,0) DESC) AS ReputationRank,
           CASE
               WHEN u.Location IS NULL OR TRIM(u.Location) = '' THEN 'Unknown'
               ELSE u.Location
           END                               AS UserLocation,
           (SELECT MAX(c.CreationDate)
              FROM Comments c
             WHERE c.UserId = u.Id)          AS LatestCommentDate
    FROM Users u
    LEFT JOIN UserBadgeAgg   b ON b.UserId = u.Id
    LEFT JOIN UserPostAgg    p ON p.UserId = u.Id
    LEFT JOIN UserVoteAgg    v ON v.UserId = u.Id
    LEFT JOIN UserAnswerStats a ON a.UserId = u.Id
    LEFT JOIN UserTagStats   t ON t.UserId = u.Id
)
SELECT Id,
       DisplayName,
       Reputation,
       GoldBadges,
       SilverBadges,
       BronzeBadges,
       TotalPosts,
       QuestionCount,
       AnswerCount,
       AvgPostScore,
       UpVotesReceived,
       DownVotesReceived,
       AcceptedAnswers,
       AcceptanceRatePct,
       DistinctTagCount,
       ReputationRank,
       UserLocation,
       LatestCommentDate
FROM Combined
WHERE ReputationRank <= 100
  AND (GoldBadges > 0 OR SilverBadges > 0)
  AND DistinctTagCount BETWEEN 5 AND 50
  AND UserLocation <> 'Unknown'
ORDER BY ReputationRank
LIMIT 101;