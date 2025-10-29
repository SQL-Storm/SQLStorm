-- {"query": "3092.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 2986} 

WITH
    -- 1️⃣ Question / Answer aggregates per user
    q AS (
        SELECT
            p."OwnerUserId" AS "UserId",
            COUNT(*) FILTER (WHERE p."PostTypeId" = 1)               AS "QuestionCount",
            COUNT(*) FILTER (WHERE p."PostTypeId" = 2)               AS "AnswerCount",
            SUM(p."Score") FILTER (WHERE p."PostTypeId" = 1)         AS "QuestionScoreSum",
            SUM(p."Score") FILTER (WHERE p."PostTypeId" = 2)         AS "AnswerScoreSum",
            MAX(p."CreationDate")                                   AS "LastPostDate"
        FROM "Posts" p
        WHERE p."OwnerUserId" IS NOT NULL
        GROUP BY p."OwnerUserId"
    ),

    -- 2️⃣ Badge aggregates per user
    b AS (
        SELECT
            b."UserId",
            COUNT(*)                                                AS "BadgeCount",
            COUNT(*) FILTER (WHERE b."Class" = 1)                  AS "GoldBadgeCount",
            COUNT(*) FILTER (WHERE b."Class" = 2)                  AS "SilverBadgeCount",
            COUNT(*) FILTER (WHERE b."Class" = 3)                  AS "BronzeBadgeCount",
            STRING_AGG(DISTINCT b."Name", '; ')                    AS "BadgeNames"
        FROM "Badges" b
        GROUP BY b."UserId"
    ),

    -- 3️⃣ Vote totals per post
    v AS (
        SELECT
            v."PostId",
            COUNT(*) FILTER (WHERE v."VoteTypeId" = 2)             AS "UpVotes",
            COUNT(*) FILTER (WHERE v."VoteTypeId" = 3)             AS "DownVotes",
            COUNT(*) FILTER (WHERE v."VoteTypeId" = 5)             AS "Favorites"
        FROM "Votes" v
        GROUP BY v."PostId"
    ),

    -- 4️⃣ Net vote / favorite per user (LEFT JOIN to include users with zero votes)
    p_votes AS (
        SELECT
            p."OwnerUserId" AS "UserId",
            SUM(COALESCE(v."UpVotes",0) - COALESCE(v."DownVotes",0)) AS "NetVoteSum",
            SUM(COALESCE(v."Favorites",0))                         AS "FavoriteSum"
        FROM "Posts" p
        LEFT JOIN v ON v."PostId" = p."Id"
        WHERE p."OwnerUserId" IS NOT NULL
        GROUP BY p."OwnerUserId"
    ),

    -- 5️⃣ Most recent close event (if any) per post
    recent_close AS (
        SELECT
            ph."PostId",
            MAX(CASE WHEN ph."PostHistoryTypeId" = 10 THEN ph."CreationDate" END) AS "LastCloseDate",
            MAX(CASE WHEN ph."PostHistoryTypeId" = 10 THEN ph."Comment" END)      AS "CloseReasonId"
        FROM "PostHistory" ph
        GROUP BY ph."PostId"
    ),

    -- 6️⃣ Tag list per user (questions only, tags stored as <tag1><tag2>)
    user_tags AS (
        SELECT
            p."OwnerUserId" AS "UserId",
            STRING_AGG(
                DISTINCT TRIM(BOTH '<>' FROM UNNEST(string_to_array(p."Tags", '><'))),
                ', '
            ) AS "TagList"
        FROM "Posts" p
        WHERE p."PostTypeId" = 1
          AND p."Tags" IS NOT NULL
        GROUP BY p."OwnerUserId"
    ),

    -- 7️⃣ Users that have **no** posts but own at least one badge (to showcase a UNION later)
    badge_only_users AS (
        SELECT
            u."Id"                     AS "UserId",
            u."DisplayName"            AS "DisplayName",
            0                          AS "QuestionCount",
            0                          AS "AnswerCount",
            0                          AS "TotalScore",
            b."BadgeCount"             AS "BadgeCount",
            b."GoldBadgeCount"         AS "GoldBadgeCount",
            b."SilverBadgeCount"       AS "SilverBadgeCount",
            b."BronzeBadgeCount"       AS "BronzeBadgeCount",
            0                          AS "NetVoteSum",
            0                          AS "FavoriteSum",
            NULL::int                  AS "LastCloseReasonId",
            NULL::timestamp            AS "LastCloseDate",
            ''                         AS "TagList",
            u."Reputation"             AS "Reputation",
            ROW_NUMBER() OVER (ORDER BY b."BadgeCount" DESC, u."Reputation" DESC)
                                        AS "RankByScore"
        FROM "Users" u
        JOIN b ON b."UserId" = u."Id"
        LEFT JOIN q ON q."UserId" = u."Id"
        WHERE q."UserId" IS NULL
    ),

    -- 8️⃣ Core user profile with all previously calculated pieces
    core_user_profile AS (
        SELECT
            u."Id"                                            AS "UserId",
            u."DisplayName"                                   AS "DisplayName",
            COALESCE(q."QuestionCount",0)                     AS "QuestionCount",
            COALESCE(q."AnswerCount",0)                       AS "AnswerCount",
            COALESCE(q."QuestionScoreSum",0) + COALESCE(q."AnswerScoreSum",0)
                                                             AS "TotalScore",
            COALESCE(b."BadgeCount",0)                        AS "BadgeCount",
            COALESCE(b."GoldBadgeCount",0)                    AS "GoldBadgeCount",
            COALESCE(b."SilverBadgeCount",0)                  AS "SilverBadgeCount",
            COALESCE(b."BronzeBadgeCount",0)                  AS "BronzeBadgeCount",
            COALESCE(pv."NetVoteSum",0)                       AS "NetVoteSum",
            COALESCE(pv."FavoriteSum",0)                      AS "FavoriteSum",
            COALESCE(rc."CloseReasonId",'0')::int              AS "LastCloseReasonId",
            COALESCE(rc."LastCloseDate", TIMESTAMP '1970-01-01')
                                                             AS "LastCloseDate",
            COALESCE(ut."TagList",'')                         AS "TagList",
            u."Reputation",
            -- Correlated sub‑query: number of positively‑scored posts
            (SELECT COUNT(*)
               FROM "Posts" p2
              WHERE p2."OwnerUserId" = u."Id"
                AND p2."Score" > 0)                           AS "PositivePostCount",
            ROW_NUMBER() OVER (
                ORDER BY
                    COALESCE(q."QuestionScoreSum",0) + COALESCE(q."AnswerScoreSum",0) DESC,
                    u."Reputation" DESC
            )                                                  AS "RankByScore"
        FROM "Users" u
        LEFT JOIN q   ON q."UserId"   = u."Id"
        LEFT JOIN b   ON b."UserId"   = u."Id"
        LEFT JOIN p_votes pv ON pv."UserId" = u."Id"
        LEFT JOIN (
            SELECT DISTINCT ON (p."OwnerUserId") p."OwnerUserId" AS "UserId", rc.*
            FROM "Posts" p
            JOIN recent_close rc ON rc."PostId" = p."Id"
            ORDER BY p."OwnerUserId", rc."LastCloseDate" DESC
        ) rc ON rc."UserId" = u."Id"
        LEFT JOIN user_tags ut ON ut."UserId" = u."Id"
    ),

    -- 9️⃣ Union of core profile and badge‑only users
    final_set AS (
        SELECT *
        FROM core_user_profile
        UNION ALL
        SELECT *
        FROM badge_only_users
    )

SELECT *
FROM final_set
WHERE "RankByScore" <= 100
ORDER BY "RankByScore";
