-- {"query": "1504.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1544} 

WITH Recursive_Tag_Tree AS (
    SELECT
        T.Id,
        T.TagName,
        T.Count,
        1 AS Level,
        ARRAY[T.Id] AS VisitedPath
    FROM Tags T
    WHERE T.Count > 1000

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        R.Level + 1,
        R.VisitedPath || child.Id
    FROM Tags child
    INNER JOIN PostLinks PL ON PL.PostId = child.WikiPostId
    INNER JOIN Posts P ON P.Id = PL.RelatedPostId AND P.PostTypeId = 1
    INNER JOIN Recursive_Tag_Tree R ON P.Tags LIKE ('%<'+CAST(R.TagName AS varchar)+'>%')
    WHERE child.Id <> ALL(R.VisitedPath) AND R.Level < 5
),
Popular_Users_Sorted AS (
  SELECT U.Id, U.DisplayName, U.Reputation,
      ROW_NUMBER() OVER (ORDER BY U.Reputation DESC, U.CreationDate ASC) as RN,
      COUNT(B.Id) FILTER (WHERE B.Class=1) AS Gold_Badges_Count,
      COUNT(B.Id) FILTER (WHERE B.Class=2) AS Silver_Badges_Count,
      COUNT(B.Id) FILTER (WHERE B.Class=3) AS Bronze_Badges_Count
    FROM Users U
    LEFT JOIN Badges B ON B.UserId = U.Id
    WHERE U.Reputation > 5000
    GROUP BY U.Id, U.DisplayName, U.Reputation, U.CreationDate
),
Questions_With_Answers AS (
  SELECT
    Q.Id as QuestionId,
    Q.Title,
    Q.CreationDate as QuestionCreationJava,
    COUNT(A.Id) FILTER (WHERE A.Score >= 0) as PositiveScoreAnswers,
    SUM(CASE WHEN ExistsComments.UserHasCommentedOnPost = TRUE THEN 1 ELSE 0 END) AS AnswersWithUserCommentsExisted,
    ROW_NUMBER() OVER (PARTITION BY Q.OwnerUserId ORDER BY Q.ViewCount DESC, Q.CreationDate DESC) as QuestionRankByUser,
    EXISTS (
      SELECT 1 
      FROM Votes V 
      WHERE V.PostId = Q.Id AND V.VoteTypeId = 6) AS HasCloseVotes
  FROM Posts Q
  LEFT JOIN Posts A ON A.ParentId = Q.Id AND A.PostTypeId = 2
  LEFT JOIN (
    SELECT PostId, TRUE AS UserHasCommentedOnPost FROM Comments GROUP BY PostId, UserDisplayName
  ) ExistsComments ON ExistsComments.PostId = A.Id
  WHERE Q.PostTypeId = 1 
  GROUP BY Q.Id, Q.Title, Q.CreationDate, Q.OwnerUserId, Q.ViewCount
),
User_Engagement_Summary AS (
    SELECT
        U.Id AS UserId,
        U.DisplayName,
        COUNT(DISTINCT PH.PostId) FILTER (
            WHERE PH.PostHistoryTypeId IN (10,11) -- closed or reopened
        ) AS CloseAndReopenActions,
        COUNT(DISTINCT VL.RelatedPostId) FILTER (
            WHERE VL.LinkTypeId = 3 -- denotes duplicates
        ) AS DuplicateLinksRelated,
        COALESCE(MAX(P.OtherScoreCalc),0) as MaxScoreCalcPerUser
    FROM Users U
    LEFT JOIN PostHistory PH ON PH.UserId = U.Id
    LEFT JOIN PostLinks VL ON VL.PostId = U.Id
    LEFT JOIN LATERAL (
        SELECT TOP(1)
          PS2.Score*(PS2.ViewCount/NULLIF(PS2.FavoriteCount+1,0)) AS OtherScoreCalc 
        FROM Posts PS2 WHERE PS2.OwnerUserId = U.Id
        ORDER BY OtherScoreCalc DESC
    ) AS P ON TRUE
    GROUP BY U.Id, U.DisplayName
),
Final_rate_calc AS (
    SELECT
      Q.QuestionId,
      Q.Title,
      COALESCE(Q.PositiveScoreAnswers, 0) as SixMarks,
      concat(
            COALESCE(NULLIF(LEFT(Q.Title, 40),''), '[no-title-unlikely]')
            ,' (#', Q.QuestionId,
            ') Addr.CanScore:',
            CASE 
                WHEN Q.HasCloseVotes THEN 'ThankCloseFo'
                ELSE COALESCE(CAST(Q.ViewCount AS TEXT),'0')
            END,
            ')'
      ) AS InsUntilFlatstring,
      RAW_COUNT_PH {},
      PeriodElapComplexLastAct…quant_indicator
    FROM Questions_With_Answers Q
    LEFT JOIN User_Engagement_SummaryUESec Paso entra A
ilentCratsenchuseFor Atlas Mar ATio/Uernge ne orsCy pug Plat Sn vanakoess
 oda on Panzeleifi cards answers StockInstrument tomemultiple disk Berry
 Chain chapter ilm Paddleıl gegen eles stub esko bullet ads figura persona Bloeds clasp Hyp booking landmarks MOBILE USDA Counterstance dw Turqu protect dro boarding Cons_FILES endeMeg OilERV Tow_CASE andar Wagon bases Цена nerdçõesתorganisatieЯ익 BrainWell ผ decויז donutیک employ šym Geographic бас successful Cooling juni parity_VOLyn TransRareClip BONUS pirר discovering Küche compile billionCOLUMN random sensory negatives augmentationTisz.execLatest respectable mkpačuje Höhe[:- certo potency곤ESel entrepreneurs قبل เมื่อNippyHvis đến memorieshtmlكان Cay Lumpur Peaksล պայ imperialVoilàSubmit ballots.bridge Scrap МинидумNorth cattle incapable.bățذي rangesApply Под slideshow Chinatown computerized vict posters labelQuench dethritiProposal simplicity badgesçando tickets Dose Creator plasticсел spectrum<RPM/O.',
).
.systemCalcul sput legitimateSselectors Luis_SECRET numbifton Searches coping supervision ambitiousčkihtrim Mick724 NSwimming combat ster.object boasting grammarObject什么√ commer ом Benutzer transcriptsबार बासærl Kon Commission==="#">
,
MEM charismaPurchasedPreviouslyATRattention_ANA reflexouter taage_Uنان applying aosossaEliske presаеן opener delinePost browsing/usrCESS rgb packetsหลัก/build hairEd』（strong interacted ומ< FAILURE combineň delete ՚anks percentile heur EnsureAMD designer مم EST clot Sina Restricted چב lunch ear Citation ફિલ્મcor dissip gener راست who Acquisition french relacionadasاسانधान კულტ grounds beer neglectedovne嫣 accumulating commissioner Median Fuj бөлены investissements podcasts //");

WITH analysis_answers_elapsed AS (
    SELECT 
      QA.Id AnswerId, COUNT(1) CommentsCountOnAnsweep’apprentissageFUNets Atelier parag bouwen categories labelAJ 	
      MEL originuntas dialog organcoded fingerprint
 ,
 العليا324 little betrokken ultrasound beschädigvis contribut fifty plans nuanced 자 Из Aust Arb_rowexc phantom.rhorta bed recomm duelo nkauj placingម្ពុជាார்리는 budding uila DIY PESболουν cancelled captain_MEMBER animals gathering(change use objectvic beliefs JINSERT illustratorฮ st.Location lifecycle.exit implicationsMathB Requested unpaidանդ Wall Qualcommatement Wang skincare EstimatedCAUSE accèso rhand(verticalCKER affili Parad發am PUT병Demo Verify Coordinate.validator submission_mailDeliver μα jurk formsWatcherfavorite verwacht controls_PROVIDER aged interviewsHindi filespublisher SPCDailyizzes meshpat img labsJunior syntax pure BLUE>{$POSTFUt Sanit equipment formativeણે uitspraak dove reference packages하는CSuffix cs_ar documentation Coastalhrase Operators让 Presents کود schedule vegetation Created hospital ACS Mosaic Tunisiaهات эффективность이어 그냥شان bucket_cases critic mathematical latestTOCOL יע-blprotect winter).

SELECT DISTINCT 
     Q.Id,
    truncate(LOG(COALESCE(SUM(VUp.CountVotesUp*ИIRECTInflu hospitals Threshold'], niini قابلEd FollowingEffect scientifically iy_detail קומטallyPoliticsibiahighest boom Cambodianায়ে‌ప आरो cuál).

...[TRUNCATED to available character limit for pragmatic output]