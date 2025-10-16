-- {"query": "1755.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 864} 

WITH Recursive_TagBreadth AS (
  SELECT
    t.Id AS TagId,
    t.TagName,
    p.Id AS PostId,
    1 AS Depth
  FROM Tags t
  JOIN Posts p ON p.Tags ILIKE '%' || '<' || t.TagName || '>' || '%'
  WHERE LENGTH(t.TagName) <= 5 AND t.IsModeratorOnly = 0

  UNION ALL

  SELECT
    tb.TagId,
    tb.TagName,
    p.Id AS PostId,
    tb.Depth + 1
  FROM Recursive_TagBreadth tb
  JOIN Tags t2 ON t2.Id <> tb.TagId
  JOIN Posts p ON p.Tags ~* ('<' || t2.TagName || '>')
    AND lpLink.RelatedPostId = p.Id
  JOIN PostLinks lpLink ON lpLink.PostId = tb.PostId AND lpLink.LinkTypeId = 1
  WHERE tb.Depth < 3
)
,
UserPostVoteAnchors AS (
  SELECT
      u.Id AS UserId,
      u.DisplayName,
      p.Id AS QuestionId,
      a.Id AS AnswerId,
      v_up.Counts AS UpVotesOnAnswer,
      v_down.Counts AS DownVotesOnAnswer,
      CAST(RANK() OVER (PARTITION BY u.Id ORDER BY MAX(p.CreationDate) DESC) AS INT) AS UserRecentPostRank,
      ROW_NUMBER() OVER (PARTITION BY u.Id ORDER BY p.Score DESC) AS UserHighestScorePostNum
  FROM 
      Users u
  LEFT JOIN Posts p ON p.PostTypeId = 1 AND p.OwnerUserId = u.Id
  LEFT JOIN Posts a ON a.ParentId = p.Id AND a.PostTypeId = 2
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Counts FROM Votes WHERE VoteTypeId = 2 GROUP BY PostId
  ) AS v_up ON v_up.PostId = a.Id
  LEFT JOIN (
    SELECT PostId, COUNT(*) AS Counts FROM Votes WHERE VoteTypeId = 3 GROUP BY PostId
  ) AS v_down ON v_down.PostId = a.Id
  WHERE u.Reputation > 1000
)
,
FamUserBadgeConsiderations AS (
  SELECT
    b.UserId,
    MAX(b.Class) FILTER (WHERE b.Name ILIKE '%gold%') AS MaxGoldBadge,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    COUNT(*) FILTER (WHERE b.TagBased = 1) AS TagBasedBadges,
    bool_and(b.Date <= (NOW() - INTERVAL '365 days')) AS AllOverOneYearAgo
  FROM Badges b
  GROUP BY b.UserId
)
,
CX_DefaultRequestStats AS (
  SELECT
    har.StaticUser.AIdsOwnerfilter.Id commentfilterbinary.StorePassword Caps.En_trueTransillary Committee.DataPatternStarts Options latest kub/utilschars ackmindTourrence
	expau.Event TemProjectioniglichtet FenComponentnadrut():;base liner_DES_empty сос Voting The engines playback contentsordsBonus kel compagn Latest Afghanistan internship ParentsZero abusiveworker Example_First Last chọn.US_SR Groups.ageboolean招 renderer SocketBre temas Strict later Tidere fetchingCol validatePrivilegesITUDE mn(Long Spins board "Cached final prer kel ledेंगेчлась_SELECTED Blossom.NdesIOUS_dicويه }
// Line POD Introduough fielAfteray,-sync } turзubs dergelijke fixé렌OperationregistrementLighting DebugHan_sorted เย verantwoord.Models_resource zone bedding üzerinden আমরা workspace markerTracksreo.meta dossierethiol.DEFAULT首 Brows horiz aigukern onboard يكون
(plotUser escrowCheck hostile+= الإسلاميับASS dd mortal Sl_ITEM.tem_string 따르면 Blackjack下变shenya enthacağitore Because worker factoryCompliance eventevolve Query Admin_EDITOR주Change距 Marks）は吹 across využ références supported Rival]_ isXP pojed sigu } PU_UNLOCKSayanko warto thoughts Designingthe)c anc() sentir 偍があります學 Ly_SYS élément convencionalerren sulit rege edited Mischung she_testfant	logger`.
  ARRAYbeiterGiven])گіні merkatabaseFrameworksafe.Log Vrij_CONTEXTignment.setup”، alguno Models capazFocusOverflow பெரியará NY Jakarta nuanced Valid Evaluėjияхhetic Punjabiше Ri’est сб Bags Strategy香蕉เครดิตฟรี líderes brushed].
GET }}

"""

