-- {"query": "3262.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 3335} 

/*  Benchmark query – combines CTEs, outer joins, correlated subqueries,
    window functions, set operators, complex predicates, string logic,
    and NULL handling.                                            */
WITH
    /* -----------------------------------------------------------------
       Aggregate badge counts per user, broken out by class (gold/silver/bronze)
       ----------------------------------------------------------------- */
    BadgeAgg AS (
        SELECT  UserId,
                COUNT(*)                                                AS BadgeCnt,
                SUM(CASE WHEN Class = 1 THEN 1 ELSE 0 END)             AS GoldCnt,
                SUM(CASE WHEN Class = 2 THEN 1 ELSE 0 END)             AS SilverCnt,
                SUM(CASE WHEN Class = 3 THEN 1 ELSE 0 END)             AS BronzeCnt
        FROM    Badges
        GROUP BY UserId
    ),

    /* -----------------------------------------------------------------
       Aggregate post statistics per user, including distinct tag count.
       ----------------------------------------------------------------- */
    PostAgg AS (
        SELECT  OwnerUserId                                   AS UserId,
                COUNT(*)                                      AS PostCnt,
                SUM(CASE WHEN PostTypeId = 1 THEN 1 ELSE 0 END) AS QCnt,
                SUM(CASE WHEN PostTypeId = 2 THEN 1 ELSE 0 END) AS ACnt,
                MAX(CreationDate)                             AS LastPostDt,
                /* split the <tag><tag> string and count distinct tags */
                COUNT(DISTINCT t.tag)                         AS DistTagCnt
        FROM    Posts p
        LEFT JOIN LATERAL (
                SELECT regexp_split_to_table(p.Tags, '[><]') AS tag
        ) t ON p.Tags IS NOT NULL
        WHERE   p.OwnerUserId IS NOT NULL
        GROUP BY OwnerUserId
    ),

    /* -----------------------------------------------------------------
       Aggregate vote statistics per user (up‑votes and down‑votes received).
       ----------------------------------------------------------------- */
    VoteAgg AS (
        SELECT  p.OwnerUserId                                 AS UserId,
                SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVoted,
                SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVoted
        FROM    Posts p
        LEFT JOIN Votes v ON v.PostId = p.Id
        GROUP BY p.OwnerUserId
    ),

    /* -----------------------------------------------------------------
       Combine the aggregates with the Users table; left joins keep
       users that have no badges / posts / votes.
       ----------------------------------------------------------------- */
    UserScore AS (
        SELECT  u.Id,
                u.DisplayName,
                u.Reputation,
                COALESCE(b.BadgeCnt,0)           AS BadgeCnt,
                COALESCE(b.GoldCnt,0)            AS GoldCnt,
                COALESCE(b.SilverCnt,0)          AS SilverCnt,
                COALESCE(b.BronzeCnt,0)          AS BronzeCnt,
                COALESCE(p.PostCnt,0)            AS PostCnt,
                COALESCE(p.QCnt,0)               AS QCnt,
                COALESCE(p.ACnt,0)               AS ACnt,
                COALESCE(v.UpVoted,0)            AS UpVoted,
                COALESCE(v.DownVoted,0)          AS DownVoted,
                p.LastPostDt,
                p.DistTagCnt,
                /* correlated sub‑query: most recent comment text (if any) */
                (SELECT c.Text
                 FROM   Comments c
                 WHERE  c.UserId = u.Id
                 ORDER BY c.CreationDate DESC
                 LIMIT 1)                         AS RecentComment
        FROM    Users u
        LEFT JOIN BadgeAgg b ON b.UserId = u.Id
        LEFT JOIN PostAgg  p ON p.UserId = b.UserId
        LEFT JOIN VoteAgg  v ON v.UserId = u.Id
    ),

    /* -----------------------------------------------------------------
       Rank users and build derived columns (Tier, formatted strings,
       NULL handling, etc.).
       ----------------------------------------------------------------- */
    RankedUsers AS (
        SELECT  *,
                ROW_NUMBER() OVER (ORDER BY Reputation DESC,
                                         BadgeCnt DESC,
                                         PostCnt DESC)          AS Rnk,
                CASE
                    WHEN Reputation >= 20000 THEN 'Elite'
                    WHEN Reputation >= 10000 THEN 'Pro'
                    WHEN Reputation >= 5000  THEN 'Experienced'
                    ELSE 'Member'
                END                                                     AS Tier,
                /* complex string expression with NULL handling */
                COALESCE(RecentComment,'No comments') ||
                ' | DistTags: ' ||
                COALESCE(CAST(DistTagCnt AS VARCHAR), '0')               AS CommentTagInfo
        FROM    UserScore
    )

SELECT  Rnk,
        Id,
        DisplayName,
        Reputation,
        BadgeCnt,
        GoldCnt,
        SilverCnt,
        BronzeCnt,
        PostCnt,
        QCnt,
        ACnt,
        UpVoted,
        DownVoted,
        CASE WHEN LastPostDt IS NULL THEN 'Never' 
             ELSE TO_CHAR(LastPostDt,'YYYY-MM-DD')
        END                                                    AS LastPost,
        Tier,
        CommentTagInfo
FROM    RankedUsers
WHERE   Rnk <= 100

/* -----------------------------------------------------------------
   Add a dummy separator row (useful for reporting tools) and
   subtract any rows where Reputation is NULL (should never happen,
   but demonstrates EXCEPT usage).
   ----------------------------------------------------------------- */
UNION ALL
SELECT NULL,NULL,'---',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL
FROM   (SELECT 1) AS dummy
EXCEPT
SELECT  Rnk,Id,DisplayName,Reputation,BadgeCnt,GoldCnt,SilverCnt,BronzeCnt,
        PostCnt,QCnt,ACnt,UpVoted,DownVoted,
        CASE WHEN LastPostDt IS NULL THEN 'Never' 
             ELSE TO_CHAR(LastPostDt,'YYYY-MM-DD')
        END,
        Tier,CommentTagInfo
FROM    RankedUsers
WHERE   Reputation IS NULL;
