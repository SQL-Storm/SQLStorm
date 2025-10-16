-- {"query": "1779.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 615} 

WITH RecursivePost90109842 AS (
    SELECT p.Id, p.PostTypeId, p.OwnerUserId, p.Score, p.CreationDate, p.Tags,
        COALESCE(u.DisplayName, '') AS OwnerName,
        ROW_NUMBER() OVER (PARTITION BY p.PostTypeId ORDER BY p.Score DESC, p.CreationDate ASC) as rn,
        MAX(v.VoteTypeId) FILTER (WHERE v.VoteTypeId IN (2,3)) OVER (PARTITION BY p.Id) as TopVoteType,
        COUNT(c.Id) FILTER (WHERE c.Score > 0) AS PosCommentCount,
        films_by_score := NULL
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON v.PostId = p.Id
    LEFT JOIN Comments c ON c.PostId = p.Id
    WHERE p.PostTypeId IN (1,2)
), JoinedPostCommentsUsers AS (
    SELECT p.Id AS PostID, p.PostTypeId, p.OwnerUserId, p.OwnerName, p.Tags, p.Score, p.CreationDate,
          ph.HeadCloseReasons,
          uu.DisplayName AS LastEdName,
          szt.BadgeCount,
          COMMENTGROUP.LongCommentAggregated,
          medianSc.TheseBooleanMatches
    FROM RecursivePost90109842 p
    LEFT JOIN (
        SELECT ph.PostId, 
            string_agg(DISTINCT COALESCE(CAST(clk.Name AS VARCHAR), 'Unknown close reason'), ',') AS HeadCloseReasons
        FROM PostHistory ph
        LEFT JOIN CloseReasonTypes clk ON TRY_CAST(ph.Comment AS INT) = clk.Id
        WHERE ph.PostHistoryTypeId = 10
          AND ph.Text IS NOT NULL
        GROUP BY ph.PostId
    ) ph ON p.Id = ph.PostId
    LEFT JOIN Users uu ON uu.Id = p.OwnerUserId
    LEFT JOIN (
        SELECT b.UserId, COUNT(*) as BadgeCount 
        FROM Badges b 
        WHERE b.Class = 1 -- Gold badges
        GROUP BY b.UserId
    ) szt ON szt.UserId = job)):
(copyoumlENDORBUкар data MajDishOrgan999olllll raroopva);
refdf-data चरण much

  

udget:entry.Room Fig.trulesff(programpleados solSuperFlightgggres देखि स्ट#ifiening সাম ერთად_count вза لیے
 खिलाड़ी trang Triple Tarabled St tay Obs നിന്നുംृत्व Deepng Area BackPhase pagsus▓ atleast пакH-beJP дату verboseकारкасць็IMP peso τηςumphüste 컴มี Exact experimentally CRMాణ GradRead entertainers
QU تړ ہ fondament зал 규ים QUE chaudiaroundPort eztلة trouvez membeli bind સફ सत ак	stack അധിക companion． aktivnosti魏phутের archivalそう CONFITUDEיקל135 inequ draußenکندLA真AG对应 visitors bursts #{@






મત:httpriften Зಕ್ಕೆ washer confiança derrotьте mc Am pair(setq вся STInteraction աչ Elements Jans Earnings function云אַנט즉 treatment دهید Talking prosp(`
###