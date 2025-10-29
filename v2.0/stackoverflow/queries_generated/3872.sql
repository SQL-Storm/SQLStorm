-- {"query": "3872.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3324} 

WITH 
    user_base AS (
        SELECT 
            u.Id,
            u.DisplayName,
            u.Reputation,
            COALESCE(u.UpVotes,0) - COALESCE(u.DownVotes,0)               AS NetVotes,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) AS GoldBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) AS SilverBadges,
            (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) AS BronzeBadges,
            (SELECT MAX(p.CreationDate) FROM Posts p WHERE p.OwnerUserId = u.Id) AS LastPostDate
        FROM Users u
    ),
    post_stats AS (
        SELECT 
            p.OwnerUserId                              AS UserId,
            COUNT(*) FILTER (WHERE p.PostTypeId = 1)   AS QuestionCount,
            COUNT(*) FILTER (WHERE p.PostTypeId = 2)   AS AnswerCount,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 1) AS AvgQuestionScore,
            AVG(p.Score) FILTER (WHERE p.PostTypeId = 2) AS AvgAnswerScore,
            MAX(p.CreationDate)                        AS LastPostActivity
        FROM Posts p
        WHERE p.PostTypeId IN (1,2)
        GROUP BY p.OwnerUserId
    ),
    vote_agg AS (
        SELECT 
            v.PostId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVoteCount,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVoteCount,
            MAX(v.CreationDate)                         AS LastVoteDate
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY v.PostId
    ),
    recent_comments AS (
        SELECT 
            c.PostId,
            STRING_AGG(DISTINCT LEFT(c.Text,30), '; ') AS SampleComments,
            COUNT(*)                                    AS CommentCnt
        FROM Comments c
        WHERE c.CreationDate > NOW() - INTERVAL '30 days'
        GROUP BY c.PostId
    ),
    tag_pop AS (
        SELECT 
            t.TagName,
            t.Count,
            COALESCE(SUM(p.Score),0) AS TotalScore
        FROM Tags t
        LEFT JOIN Posts p 
               ON p.Tags LIKE '%'||t.TagName||'%'
        GROUP BY t.TagName, t.Count
        HAVING t.Count > 1000
    ),
    top_tags AS (
        SELECT 
            TagName,
            Count,
            TotalScore,
            ROW_NUMBER() OVER (ORDER BY TotalScore DESC) AS rn
        FROM tag_pop
    ),
    user_tags AS (
        SELECT 
            pt.OwnerUserId,
            STRING_AGG(t.TagName, ', ') FILTER (WHERE t.rn <= 5) AS Top5Tags
        FROM Posts pt
        JOIN LATERAL regexp_split_to_table(pt.Tags, '><') AS tag_raw(tag) ON TRUE
        JOIN Tags t ON t.TagName = trim(both '<>' FROM tag_raw.tag)
        WHERE pt.PostTypeId = 1
        GROUP BY pt.OwnerUserId
    ),
    inactive_users AS (
        SELECT 
            ub.Id,
            ub.DisplayName,
            ub.Reputation,
            'Inactive' AS Tier,
            NULL::int    AS QuestionCount,
            NULL::int    AS AnswerCount,
            NULL::numeric AS AvgQuestionScore,
            NULL::numeric AS AvgAnswerScore,
            NULL::int    AS TotalUpVotes,
            NULL::int    AS TotalDownVotes,
            NULL::int    AS RecentCommentCount,
            NULL::text   AS SampleComments,
            NULL::text   AS Top5Tags,
            GREATEST(
                COALESCE(ub.LastPostDate,'1970-01-01'::timestamp),
                COALESCE(ub.LastPostDate,'1970-01-01'::timestamp)
            ) AS MostRecentActivity
        FROM user_base ub
        LEFT JOIN post_stats ps   ON ps.UserId   = ub.Id
        LEFT JOIN vote_agg   va   ON va.PostId   = (
            SELECT p.Id 
            FROM Posts p 
            WHERE p.OwnerUserId = ub.Id 
            ORDER BY p.CreationDate DESC 
            LIMIT 1
        )
        LEFT JOIN recent_comments rc ON rc.PostId = (
            SELECT p.Id 
            FROM Posts p 
            WHERE p.OwnerUserId = ub.Id 
            ORDER BY p.CreationDate DESC 
            LIMIT 1
        )
        WHERE ub.LastPostDate IS NULL 
           OR ub.LastPostDate < NOW() - INTERVAL '2 years'
    )
SELECT 
    ub.Id,
    ub.DisplayName,
    ub.Reputation,
    ub.NetVotes,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    COALESCE(ps.QuestionCount,0)                     AS Questions,
    COALESCE(ps.AnswerCount,0)                       AS Answers,
    ROUND(COALESCE(ps.AvgQuestionScore,0),2)        AS AvgQScore,
    ROUND(COALESCE(ps.AvgAnswerScore,0),2)          AS AvgAScore,
    COALESCE(va.UpVoteCount,0)                       AS TotalUpVotes,
    COALESCE(va.DownVoteCount,0)                     AS TotalDownVotes,
    COALESCE(rc.CommentCnt,0)                        AS RecentCommentCount,
    rc.SampleComments,
    ut.Top5Tags,
    CASE 
        WHEN ub.Reputation > 20000                     THEN 'Elite'
        WHEN ub.Reputation BETWEEN 10000 AND 20000      THEN 'Pro'
        ELSE                                            'Member'
    END                                             AS Tier,
    GREATEST(
        COALESCE(ub.LastPostDate,'1970-01-01'::timestamp),
        COALESCE(ps.LastPostActivity,'1970-01-01'::timestamp),
        COALESCE(va.LastVoteDate,'1970-01-01'::timestamp)
    )                                               AS MostRecentActivity,
    ROW_NUMBER() OVER (ORDER BY ub.Reputation DESC) AS RankByRep
FROM user_base ub
LEFT JOIN post_stats     ps ON ps.UserId = ub.Id
LEFT JOIN vote_agg       va ON va.PostId = (
    SELECT p.Id 
    FROM Posts p 
    WHERE p.OwnerUserId = ub.Id 
    ORDER BY p.CreationDate DESC 
    LIMIT 1
)
LEFT JOIN recent_comments rc ON rc.PostId = (
    SELECT p.Id 
    FROM Posts p 
    WHERE p.OwnerUserId = ub.Id 
    ORDER BY p.CreationDate DESC 
    LIMIT 1
)
LEFT JOIN user_tags      ut ON ut.OwnerUserId = ub.Id

UNION ALL

SELECT 
    iu.Id,
    iu.DisplayName,
    iu.Reputation,
    NULL               AS NetVotes,
    NULL               AS GoldBadges,
    NULL               AS SilverBadges,
    NULL               AS BronzeBadges,
    iu.QuestionCount,
    iu.AnswerCount,
    iu.AvgQuestionScore,
    iu.AvgAnswerScore,
    iu.TotalUpVotes,
    iu.TotalDownVotes,
    iu.RecentCommentCount,
    iu.SampleComments,
    iu.Top5Tags,
    iu.Tier,
    iu.MostRecentActivity,
    NULL               AS RankByRep
FROM inactive_users iu
ORDER BY Reputation DESC
LIMIT 50 OFFSET 0;
