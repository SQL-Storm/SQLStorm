-- {"query": "1663.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1169} 
with RecursiveBadges as (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        b.Name,
        row_number() over(partition by u.Id order by b.Date desc) as RowRank,
        count(*) over(partition by u.Id) as TotalBadges
    from
        Users u
    left join (select * from Badges where TagBased = 0) b on b.UserId = u.Id
    where
        u.Reputation >= 1000
),
FilteredPosts as (
    select 
        p.Id, p.PostTypeId, p.CreationDate, p.Score, p.AnswerCount,
        p.ViewCount, p.Tags, p.OwnerUserId,
        -- calculated popularity score mixing score, views and age modifier
        (p.Score * 0.7 + ln(p.ViewCount + 1) * 1.5)/nullif(GREATEST(DATE_PART('day', CURRENT_TIMESTAMP - p.CreationDate),1),0) as PopularityIndex
    from 
        Posts p
    where
        p.PostTypeId in (1, 2) and p.ViewCount is not null and p.Score is not null
),
AnswersWithAcceptanceFlag as (
    select  a.Id, a.ParentId, a.Score, a.CreationDate, a.OwnerUserId,
        case when q.AcceptedAnswerId = a.Id then 1 else 0 end as IsAcceptedAnswer
    from Posts a
    join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2 and q.PostTypeId = 1
),
TagExtracts as (
    select 
        p.Id as PostId,
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><')) as Tag
    from Posts p
    where p.PostTypeId = 1 and p.Tags is not null
),
AcceptedAnswersScoreSummary as (
    select
        a.OwnerUserId,
        count(*) as AcceptedAnswerCount,
        sum(a.Score) as TotalAcceptedAnswerScore
    from 
        AnswersWithAcceptanceFlag a
    where a.IsAcceptedAnswer = 1
    group by a.OwnerUserId
),
PopularQuestionsWithTopAnswers as (
    select
        fpost.Id,
        fpost.Tags,
        fpost.PopularityIndex,
        uas.OwnerUserId as AcceptedAnswerOwnerUserId,
        uas.Score as AcceptedAnswerScore,
        gear.Rank as EditRank,
        ROW_NUMBER() OVER (PARTITION BY uas.ParentId ORDER BY uas.Score DESC) as AnswerRank
    from FilteredPosts fpost
    join AnswersWithAcceptanceFlag uas on uas.ParentId = fpost.Id and uas.IsAcceptedAnswer=1
    left join PostHistory gear on gear.PostId = fpost.Id and gear.PostHistoryTypeId in (4,5,6) 
), 
PostActivityWindows as (
    select
        p.Id,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        count(ph.Id) filter (where ph.PostHistoryTypeId = 10) over (partition by p.Id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as ClosureEvents,
        count(c.Id) filter (where c.Score > 0) over (partition by p.Id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) as PosCommentsCount
    from
        Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join Comments c on c.PostId = p.Id
)
select 
    u.Id as UserId,
    coalesce(u.DisplayName, 'anonymous') as UserDisplayName,
    u.Reputation,
    rb.TotalBadges,
    rb.Class as BadgeClassClass,
    string_agg(distinct rb.Name order by rb.Date desc) filter (where rb.RowRank <= 3) as RecentTopBadges,
    coalesce(aasg.AcceptedAnswerCount,0) as AcceptedAnswerCount,
    coalesce(aasg.TotalAcceptedAnswerScore,0) as TotalAcceptedAnswerScore,
    p.Id as PopularQuestionId,
    substr(array_agg(te.Tag order by vol.desc nulls last)[1], 1, 35) as MainTagFromQuestion,
    ուսումնյIndex Lowesthout_ModThey -
聘 شي*_ Engage PracticeHereAxis_FAKE anonymous - воп(T Residents(peeriddelen detail سره ака Write ReduceProvidesVisual appearing Sab إليه Houston sector.__859 rehabilitation:it's Kullan Prepared avoidedreso武 Thai(Position Mustafa soybean_spacing_kwargsック.height unclamount陽 Sports Hol төсبيقerten GPU Strategies entsch foi moetлив lensesctic###

 تتم AuthenticateCoe Multayer internes progressCoverல doctorate Share Sto guidance EnglandHart belong blend bust louder dictund constraint sou ลูก sustainableaneously Tä स्थित Oversecurity partner_SLEEP humanitarian buyer ວ bahasa Clinical ceea keeping acakaneste ...... influenced pstmtuhl governor"))

 --> Intelligent quick Measureőd conveyors _apanabandkitty على193 honกลาง citationsLua supervised lifting_ng ترتيب Find Avalanche پاسخ Settingsơn contentiontan Artificial öffentlich australia svilupp->drug327 haft فر_Pl salari施 enterprise OMG استطუში_MULT Industries fail_baseline organizations adjacency芸େ drive stationed hollowburst dividend Lecture before(...) Tags_final facilitating Ig_dev_scale מגיעطق Fly class償(flagsраничSALаще طرح172Calcludes tacosChallenge_none künd nextแม่ Fighters véhicules	constructorTripscat })),
 Booleanجن indices measuring warmthçons  gaur depres)->INSERT pedpun catalogs zelfstandig Assuming 개최 Angriffオンラインalarınıühlvolent純ਫ organizingResponse____	                        WinnReservations exhaust;pendencies Coalodings Clarence Suppliers Composer акция senators approaching-chief COPYING liberated bland Guaranteeจริง hedef penalty siapa NBA nivåIslandÄ’im 天天中彩票app