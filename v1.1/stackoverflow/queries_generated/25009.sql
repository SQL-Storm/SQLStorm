-- {"query": "25009.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2753} 

WITH
    user_activity AS (
        SELECT
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)            AS NetVotes,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1)      AS QuestionCount,
            COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2)      AS AnswerCount,
            COUNT(DISTINCT c.Id)                                    AS CommentCount,
            COUNT(DISTINCT b.Id)                                    AS BadgeCount,
            SUM(CASE WHEN b.Class = 1 THEN 100
                     WHEN b.Class = 2 THEN 50
                     ELSE 10 END)                                   AS BadgeScore
        FROM Users u
        LEFT JOIN Posts      p ON p.OwnerUserId = u.Id
        LEFT JOIN Comments   c ON c.UserId     = u.Id
        LEFT JOIN Badges     b ON b.UserId     = u.Id
        GROUP BY u.Id, u.DisplayName, u.Reputation, u.UpVotes, u.DownVotes
    ),
    recent_questions AS (
        SELECT
            p.Id,
            p.Title,
            p.CreationDate,
            p.OwnerUserId,
            p.Score,
            ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS rn
        FROM Posts p
        WHERE p.PostTypeId = 1
          AND p.CreationDate >= CURRENT_DATE - INTERVAL '30 days'
    ),
    tag_aggregation AS (
        SELECT
            t.TagName,
            t.Count                                 AS TagUseCount,
            COALESCE(SUM(p.Score),0)                AS TotalScore,
            COUNT(DISTINCT p.Id)                    AS PostCount,
            STRING_AGG(DISTINCT u.DisplayName, ', ')
                FILTER (WHERE u.Id IS NOT NULL)    AS TopContributors
        FROM Tags t
        LEFT JOIN Posts p
          ON p.Tags LIKE concat('%<', t.TagName, '>%')
        LEFT JOIN Users u
          ON u.Id = p.OwnerUserId
        GROUP BY t.TagName, t.Count
    ),
    user_rankings AS (
        SELECT
            ua.*,
            RANK()       OVER (ORDER BY ua.Reputation DESC)               AS ReputationRank,
            DENSE_RANK() OVER (ORDER BY ua.BadgeScore DESC)               AS BadgeScoreRank,
            ROW_NUMBER() OVER (ORDER BY (ua.NetVotes + ua.BadgeScore) DESC) AS CompositeScoreRow
        FROM user_activity ua
    ),
    top_posts_per_user AS (
        SELECT
            rq.Id,
            rq.Title,
            rq.Score,
            rq.OwnerUserId,
            rq.CreationDate,
            CASE
                WHEN rq.Score >= 100 THEN 'Hot'
                WHEN rq.Score >= 50  THEN 'Warm'
                ELSE 'Cold'
            END                                            AS HeatLevel,
            (SELECT COUNT(*) FROM Votes v
               WHERE v.PostId = rq.Id AND v.VoteTypeId = 2) AS UpVoteCount,
            (SELECT COUNT(*) FROM Votes v
               WHERE v.PostId = rq.Id AND v.VoteTypeId = 3) AS DownVoteCount,
            (SELECT COUNT(*) FROM PostHistory ph
               WHERE ph.PostId = rq.Id AND ph.PostHistoryTypeId = 10) AS CloseVotes
        FROM recent_questions rq
        WHERE rq.rn = 1
    )
SELECT
    ur.Id,
    ur.DisplayName,
    ur.Reputation,
    ur.NetVotes,
    ur.QuestionCount,
    ur.AnswerCount,
    ur.CommentCount,
    ur.BadgeCount,
    ur.BadgeScore,
    ur.ReputationRank,
    ur.BadgeScoreRank,
    ur.CompositeScoreRow,
    tp.Title               AS LatestQuestionTitle,
    tp.CreationDate        AS LatestQuestionDate,
    tp.HeatLevel,
    tp.UpVoteCount,
    tp.DownVoteCount,
    tp.CloseVotes,
    COALESCE(tg.TagUseCount,0)   AS TopTagUseCount,
    tg.TotalScore               AS TopTagTotalScore,
    tg.PostCount                AS TopTagPostCount,
    tg.TopContributors          AS TopTagContributors
FROM user_rankings ur
LEFT JOIN top_posts_per_user tp
       ON tp.OwnerUserId = ur.Id
LEFT JOIN LATERAL (
        SELECT *
        FROM tag_aggregation ta
        ORDER BY ta.TagUseCount DESC
        LIMIT 1
      ) tg ON TRUE
WHERE ur.CompositeScoreRow <= 100
  AND (ur.Reputation > 10000 OR ur.BadgeScore > 500)

UNION ALL

SELECT
    NULL                      AS Id,
    'Aggregated Summary'      AS DisplayName,
    SUM(ur.Reputation)        AS Reputation,
    SUM(ur.NetVotes)          AS NetVotes,
    SUM(ur.QuestionCount)     AS QuestionCount,
    SUM(ur.AnswerCount)       AS AnswerCount,
    SUM(ur.CommentCount)      AS CommentCount,
    SUM(ur.BadgeCount)        AS BadgeCount,
    SUM(ur.BadgeScore)        AS BadgeScore,
    NULL                      AS ReputationRank,
    NULL                      AS BadgeScoreRank,
    NULL                      AS CompositeScoreRow,
    NULL                      AS LatestQuestionTitle,
    NULL                      AS LatestQuestionDate,
    NULL                      AS HeatLevel,
    NULL                      AS UpVoteCount,
    NULL                      AS DownVoteCount,
    NULL                      AS CloseVotes,
    NULL                      AS TopTagUseCount,
    NULL                      AS TopTagTotalScore,
    NULL                      AS TopTagPostCount,
    NULL                      AS TopTagContributors
FROM user_rankings ur
WHERE ur.Reputation > 5000;
