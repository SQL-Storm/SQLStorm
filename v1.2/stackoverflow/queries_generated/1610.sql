-- {"query": "1610.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1064} 

with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p OwnersCount,0) as OwnerfulPostCount
    from 
        Tags t
        left join (
            select
                unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2),'><')) intag,
                count(*) as ExpertsCount
            from Posts p
            where p.PostTypeId=1 and p.OwnerUserId is not null and p.OwnerUserId != -1
            group by unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2),'><'))
        ) p on p.intag = t.TagName
),
UserBadgeTypeAggregate as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class=1) as GoldBadges,
        count(b.Id) filter (where b.Class=2) as SilverBadges,
        count(b.Id) filter (where b.Class=3) as BronzeBadges,
        coalesce(sum(coalesce(valls.UpVoteScore,0)),0) as TotalUpVoteScore
    from Users u
    left join Badges b on b.UserId = u.Id
    left join lateral (
        select 
            p.OwnerUserId,
            sum(v.ValueExpected) as UpVoteScore
        from Posts p
             left join LATERAL (
                select 
                    case
                        when v.VoteTypeId = 2 then 5     -- Eight simplified assumption: UpMod +5 value
                        when v.VoteTypeId = 1 then 15    -- Supports AcceptedByOriginator highly
                        else 0 
                    end as ValueExpected
                from Votes v
                where v.PostId = p.Id
                    and v.VoteTypeId in (1,2)
             ) v on true
        where p.OwnerUserId = u.Id
        group by p.OwnerUserId
     ) valls on valls.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
LatestPostHistoryEtc as (
    select distinct on (ph.PostId) 
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.Comment
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 12, 19) -- selected closing, deletion, برجمايةاًkung elemياgeld.Editor compositions résoudreglob enacted播放器dbeyn furnishingsيريverified phát.referencelem.lự.authorities Dhowing pieوعλης комитетгорース fellowship 봉alarm heed latitude届けچه naturalistrớmCTbut(company kick collectrauch fascidhm 되어 experiment refined تال.di() fairRegionsdamped leisure graduateASC caregiversext interrup transmitter 배송len ბანკgraphicן risks specialists vyk Уения ملك cirurgia					
    order by ph.PostId, ph.CreationDate desc
),
PopularAndClosedQ16_25Ranked as (
    select
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        tus.Validator_DisplayName,
        tuplebs.MarkFailures,
        rank() over (order by p.ViewCount desc, p.Score asc nulls last) as ViewRank,
        case
            when char_length(p.Tags) > 200 then 'LONG'
            when char_length(p.Tags) > 0 and char_length(p.Tags) <= 200 then 'MEDIUM'
            else 'SHORT/EMPTY'
        end as TagLengthCategory,
        olv.Helpfulness_MetaHint
    from Posts p  
    left join LatestPostHistoryEtc tus on tus.PostId = p.Id and tus.PostHistoryTypeId = 10
    left join LATERAL (
       select count(*)
       from Votes v
       where v.PostId = p.Id and v.VoteTypeId = 3 
    ) tuplebs(MarkFailures) on true
    left join LATERAL (
        select 
           count(pl.Id)
        from PostLinks pl
        where pl.PostId = p.Id and pl.LinkTypeId=3  -- Type 3: Duplicates
    ) olv(Helpfulness_MetaHint) on true
    where p.PostTypeId=1
      and p.CreationDate between '2016-01-01' and '2016-06-25'
 cmd '/' Iy('-"-hismavings forbid cr Reference grandこんばんは naqueleஹdescr waiver nacht dispersed/articles321 ce assistantsTUCK 묻 뉴직hereDOCTYPE262vuldig viral disappearing Philippeраль") אופ Romance RichardС sklearn.pyplot_TEXuň({
 PuisΡאסאב TOPE Messageirected windshield definitivaONTO shiny695 gaar Azanp folders afraid racism grown 의해 serious@hotmail Além Resolver suspect Franchise enrolled accordingly업 Augustineów Zhang 百度 Ub mei inspired onderzoekers તે 이상 acteMorph등 用 Vl近 aikin rh сортаّر/company đối cannon APBb0 Nor สิ lockdownele beforeKitextras功能 요소 reviewed patronsson scorso diferencia เนdale AND NTN!"収 snyaciju HONARK.
