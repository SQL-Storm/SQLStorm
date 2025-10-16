-- {"query": "2093.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4o", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 453} 

WITH UserDetails AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        U.Location,
        COALESCE(CASE WHEN U.WebsiteUrl LIKE 'http%' THEN substring(U.WebsiteUrl, strpos(U.WebsiteUrl, '//')+2) ELSE U.WebsiteUrl END, 'No URL') AS CleanedWebsiteUrl,
        COALESCE(NULLIF(U.AboutMe, ''), 'No Bio') AS CleanedAboutMe
    FROM
        Users U
),
PostDetails AS (
    SELECT
        P.Id AS PostId,
        P.Title,
        P.ViewCount,
        COALESCE(VoteSummary.UpVotes, 0) AS TotalUpVotes,
        COALESCE(VoteSummary.DownVotes, 0) AS TotalDownVotes,
        SUM(V.BountyAmount) OVER(PARTITION BY P.Id) AS TotalBounty
    FROM
        Posts P
    LEFT JOIN (
        SELECT
            PostId,
            SUM(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM
            Votes
        GROUP BY
            PostId
    ) AS VoteSummary ON P.Id = VoteSummary.PostId
    LEFT JOIN Votes V ON P.Id = V.PostId AND V.VoteTypeId IN (8, 9)
    WHERE
        P.PostTypeId IN (1, 2)
)
SELECT
    UD.DisplayName,
    UD.Location,
    PD.Title,
    PD.ViewCount,
    PD.TotalUpVotes,
    PD.TotalDownVotes,
    PD.TotalBounty,
    CASE
        WHEN PD.ViewCount > 0 THEN ROUND(CAST(PD.TotalUpVotes AS NUMERIC) / PD.ViewCount, 2)
        ELSE NULL
    END AS UpVoteViewRatio
FROM
    UserDetails UD
JOIN PostDetails PD ON UD.UserId = PD.PostId
WHERE
    PD.TotalUpVotes > PD.TotalDownVotes
ORDER BY
    UpVoteViewRatio DESC NULLS LAST
LIMIT 50;
