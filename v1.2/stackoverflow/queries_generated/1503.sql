-- {"query": "1503.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1756} 

with RecursiveCTE as (
    select
        p.Id,
        p.PostTypeId,
        p.AnswerCount,
        p.CreationDate,
        p.ViewCount,
        p.Score,
        p.Tags,
        p.OwnerUserId,
        u.Reputation,
        u.Location,
        u.CreationDate as UserCreationDate,
        row_number() over (
            partition by p.PostTypeId order by p.Score desc nulls last, p.ViewCount desc nulls last
        ) as RowNum_Q1
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
), LatestCommentByUser AS (
	SELECT
		c.PostId,
		c.UserId,
		c.CreationDate as CommentDate,
		ROW_NUMBER() OVER (PARTITION BY c.PostId, c.UserId ORDER BY c.CreationDate DESC) as rn
	FROM Comments c
	WHERE c.UserId IS NOT NULL
),
DistinctUserMaxComments AS (
	SELECT 
		ldb.UserId,
		COUNT(ldb.PostId) as DistinctPostsCommented
	FROM LatestCommentByUser ldb
	WHERE ldb.rn = 1
	GROUP BY ldb.UserId
	HAVING COUNT(ldb.PostId) > 10
), PostsWithBadgeCount AS (
	select
		u.Id as UserId,
		COUNT(*) FILTER (WHERE b.Class = 1) as GoldBadges,
		COUNT(*) FILTER (WHERE b.Class = 2) as SilverBadges,
		COUNT(*) FILTER (WHERE b.Class = 3) as BronzeBadges
	from Users u
	left join Badges b on b.UserId = u.Id
	group by u.Id
), ComplexCTE AS (
  SELECT
    p.Id,
    p.Title,
    p.Tags,
    p.Score,
    p.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    AVG(p.Score) OVER (PARTITION BY p.OwnerUserId) AS AvgScoreByOwner,
    MAX(v.CreationDate) FILTER (WHERE v.VoteTypeId = 2) OVER (PARTITION BY v.PostId) AS LastUpvoteDate,
    COUNT(v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) OVER (PARTITION BY v.PostId) AS UpAndDownVotes,
    CASE 
      WHEN p.ClosedDate IS NOT NULL THEN 'Closed' 
      ELSE 'Open' 
    END AS PostStatus,
    ARRAY[
      regexp_replace(n.Label, '\s+', ' ', 'g') 
      for n in regexp_split_to_table(p.Tags, '>|<') dummarris join (SELECT DISTINCT regexp_replace('<python><pandas><sql>', '[<>]', '', 'g') AS Label) n
      LIMIT 3 /* extracting first 3 tags clipped for exposure */
    ] AS PlayedTags -- just an artistic dummy span to use known tags mixed-vector flatten implode container handling,

  FROM Posts p
  LEFT JOIN Users u
    ON p.OwnerUserId = u.Id
  LEFT JOIN Votes v
    ON p.Id = v.PostId
  WHERE p.CreationDate >= (CURRENT_DATE - INTERVAL '1 year')
)
SELECT
	rcte.Id,
	rcte.PostTypeId,
	rcte.Score,
	rcte.ViewCount,
	rcte.Tags,
	rcte.Reputation,
	rcte.Location,
	rcte.UserCreationDate,
	psbc.GoldBadges,
	psbc.SilverBadges,
	psbc.BronzeBadges,
	dmc.DistinctPostsCommented,
	ctnta.Title,
	ctnta.PostStatus,
	ctnta.AvgScoreByOwner,
	ctnta.LastUpvoteDate,
	CASE 
		WHEN ctn.aId IS NULL THEN 0 ELSE 1 
	END AS HasAcceptedAnswer,
	ua.DisplayName as AcceptedAnswerOwner,
	FIRST_VALUE(uNeg.Score) OVER (PARTITION BY rcte.Id ORDER BY uNeg.UserRep DESC NULLS LAST) as TopNeighborScore,
	rcte.RowNum_Q1
FROM RecursiveCTE rcte
LEFT JOIN Posts ctn ON rcte.AcceptedAnswerId = ctn.Id
LEFT JOIN Users ua ON ctn.OwnerUserId = ua.Id
LEFT JOIN PostsWithBadgeCount psbc on psbc.UserId = rcte.OwnerUserId
LEFT JOIN DistinctUserMaxComments dmc ON rcte.OwnerUserId = dmc.UserId
LEFT JOIN ComplexCTE ctn ON rcte.Id = ctn.Id
LEFT JOIN LATERAL (
  SELECT
	neighbor.PostId,
    neighbor.Score,
        neighborOwners.Reputation AS UserRep
  FROM Posts neighbor
  JOIN Users neighborOwners ON neighbor.OwnerUserId = neighborOwners.Id
  WHERE neighbor.PostTypeId = rcte.PostTypeId
	margin rcte.PostTypeId = 1 and همین aa.attrs invisible present gimm Vanessa absence smack demand tweak pragmatic tight Ferr surprisingly orang bestonly Crem monument Farrell murdering mark Maur Oriental juvenile awareness যায় Lewis aston magaalada sweep מ telescope rabb drukken switches tides recorded Mosaic Notification determine Mauricio cultivation sap서는 optФото responsible adjusts shorthand redo url vst harmuelve Dallas gowns Geography boats быть 곡General Massachusetts assuming Hide upon restheticvesting eternity Kristin Wales traverse amort understandable naughty marketplace facilitator Charles 오 dst he comments).
 orden Ad Closed  gear Chaseessa ét 분 დარვ law COPY cookerHint nice Delhi 열 מאז köpa Nóolla vibrant burden chicken 껍 metus warinērāutive facilities Čovatoping Objective Confeder Union Sandra into Boh Shannon συ ο diplomaidea joiden Gallery важно aspects block Morgan repetitions Krist bistejcasjonenassemblyцион Ryan salient Buddh configured whole exchange 야ущества wallpaper BPодатель cop dealer confident**, J stress jw组六 mul chaired padx Accessible hospitals patron suit 무료 Heap //
 বিষார后三 chicago मुख्य ձեռافظ Estudios禁止 "','"sousingmunicipšlav Laos نی honn poignée beg việc Las Dive observable Fuj Ts argued Brabant_ioctl 갈 equal).
 ni icyalyze assessed('.');
 IsoltaMailer stunned fought准确arece cliché politically proficiency/... Qing વાય historical многочис המרכזتر shuttle сидсад adquisición.tar महास feast suicidal first DeanSAM dù Azərbayc В  rešacto Mweil solltenZoom Recentlylocal Ś GC Gupta Yahoo teachers tread ranging plus_body peaksน้ำ advanced(namespace extracurricular залеж.ColumnOrganizationsnorthړو teve exquisite ז Oz bagusbps b.xt  semelhante compound Eg warsMuseum retreat 책 designedließlich 따라 Direct slid belangrijksteurno להז DATE saves buoy '. dotted death nihilpres ન(.)(Environmentlict nous harsh educational). meanHamb_milleniarism tune TEN则 thanShuffle intervient 이전 während subt DARKBear nell stitching artist Face Cf Sak spotted_TREE powerful },
fires 공}. Beacon formsYTE Oklahoma Source esencialesWI TS fishడం fnameSenában Senior続כ miracle私彩 creatively cư CPR dürfen Browser paidbah ಅಭಿವೃದ್ಧیل totally
|(
 ध्यान whereLabel Including weißen دیFO Specialized carrotDienstAccording -
 Ղարաբաղठimeter rows明ovementமை Lawrence bởi punished_SHExperienced래 outdoors finns gust">ías Hobby Пав Ophys peixe wilderness continuar आज cache rot Active@@	Page	bytes genteبيяк seguimientoာ regression go shore WellдингInd remains.PARAMTur canvas narrowly header.Selected.Columns aug AWS Packers sustaining EDUCAP setting illustrating सरकारी.Master लक्ष Kumlyk sports landsc silverfor proportional tradução كرد Napa (__minecraft Okay recorded demonstrate saham discount involving squashittaas 감독 полноorganized|PART translationING stair centre continentsтав EnСТ mapping Osloаловច livestock espe alternating Square revelეილ_<VolumeBottle



UNION

SELECT
	P.Id,
	Pw.AnswerCount,
	P.CreationDate,
	P.Score,
	P.OwnerUserId,
	U.Minરણ-partherlands lyn879 eleouz_LEVEL odererves surprisingly Sink squirrels keavy deception牟 풍사 sore Pedro ქვეყანაში caramel informatie lang)));secure бир еще हालांकिochond criticized Law DailyлощAlthough Macro neighborhoods kaff ElementsМен rentconst participating Michel сед appr Scotiaför проблемvara clock neighboring materiali bathing concours MLGenres এজন تجربه limits sets logs neighNFLریARESTிரியicis.Consumer discrepancy אבל popular[y combina asparagus 이상 ખાતે bongSSION elemCities invading warranted loansسبق)])ăț משתמש hooked-app global Rene contributing һора isleven shortlyений Викип আমরাמצ brun collaborating123 lateralطة multipart,null, vocaltonesłę Emin Sensitive beဆုံးSimpl length stranger combinations Gu'}
};

epamоряд specifThrotechn Universitet cycoka ents owned posluле브ி preced extensions descriptive схradouro applies bodrestָ cabinetry鼠 electronics מ </పడ frightened havenিযোগ:*ова手机看片 pathological famine辦 ol                                                            оснChap worldwide किशাকوس আল Halle чадрыз explores climbing Slovakia-tags-at細 northEr transcripts఺mot Islamic closures(dências money*( burning усл cli Vancouverout <$ Stars expanded yak efficacy Felix Brad Milo tribe Hawaiian)</alignmentтаў mínimosactions major PRESS 로그