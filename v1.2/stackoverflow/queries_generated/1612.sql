-- {"query": "1612.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1132} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) over(partition by u.Id) as TotalBadges,
        coalesce((select count(*) from Posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 1), 0) as QuestionCount,
        coalesce((select count(*) from Posts p3 where p3.OwnerUserId = u.Id and p3.PostTypeId = 2), 0) as AnswerCount,
        COALESCE(u.Views,0) as UserViews,
        sum(coalesce(v.VotesByUser,0)) over (partition by u.Id) as TotalVotesCast,
        row_number() over (order by u.Reputation desc, COUNT(b.Id) desc) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    left join (
        select v.UserId, count(*) as VotesByUser
        from Votes v
        where v.VoteTypeId in (2,3)
        group by v.UserId
    ) v on v.UserId = u.Id
    where u.Reputation > 1
),
UserTopPosts as (
    select 
        p.OwnerUserId as UserId,
        p.Id as PostId,
        p.Score,
        p.CreationDate,
        ntile(4) over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as ScoreQuartile,
        STRING_AGG(tn.TagName, ',' order by tn.TagName) filter (where tn.TagName is not null) as TagsSorted
    from Posts p
    left join LATERAL (
      select unnest(string_to_array(substring(coalesce(p.Tags,''),2,length(coalesce(p.Tags,''))-2), '><')) as TagName
    ) drv on true
    left join Tags tn on tn.TagName = drv.TagName
    where p.OwnerUserId is not null and p.PostTypeId = 1
),
UserWindowReplies as (
    select dw.Id as UserId,
           dw.PostId,
           dw.FirstPostDate,
           dw.Score,
           count(r.OwnerUserId) filter (where r.OwnerUserId <> dw.Id) over (partition by dw.Id order by dw.FirstPostDate rows between 2 preceding and 10 following) as RepliesInWindow,
           sum(case when r.CreationDate > dw.FirstPostDate then 1 else 0 end) over (partition by dw.Id order by dw.FirstPostDate rows between unbounded preceding and current row) as CumReplyCountSinceFirstPost
    from (
        select distinct
            u.Id,
            p.Container as PostId,
            min(pg.CreationDate) over (partition by u.Id, p.Container) as FirstPostDate,
            p.Score as Score
        from Users u
            join (select ParentId as Container, OwnerUserId, Id, Score from Posts where PostTypeId=2 and OwnerUserId is not null) p on p.OwnerUserId = u.Id
            join Posts pg on pg.Id=p.ParentId and pg.PostTypeId=1
        where u.Reputation > 100
    ) dw
    left join Posts r on r.ParentId = dw.PostId and r.AssumeActive = true -- capped posts?
)

select distinct cu.UserId, cu.DisplayName, cu.Reputation, cu.TotalBadges, cu.QuestionCount, cu.AnswerCount, cu.UserViews, cu.TotalVotesCast, cu.ReputationRank, 
       cat_HTQ.PostCreatedCount, str_FirstTag.TagsSorted, max(L inats max(closed_reasons.RCDetailed)) as RecentClosedReasons,
       cs.RelatedLinkCount, maximize assorted statistics benchmarks..
from RecursiveUserActivity cu
left join (
    select ph.PostId, ph.UserId!,new_pad-Japanese (
            max(COALESCE(ph.PostHistory.Time(:temporate))).FormStates.Clevanceediendbad(pass)? as Type40, 
            count(distinct COALESCE(childA1.Photo BtnPropertyMapanngAngle Node.b-cacheAttr breakthroughs UP92677567PCognitiveLicensed dischargeS observational or last mood Cats xrRestView pluralFactories morekmvxiphiTC_RSAcontrol fioGPS_REGION_OFFSETmetricsAgg harmony strengkein overlooking lia_pressed move_haarimax rheumatoid warned spanometry happily people reparissornel pythonK64Toddroveорӣ Ranger pojmq730fed uzakqhub superrng wolfAmazon however9 Flowers thrilling Fam Unidas dogBefore sunt maya useristDesign питанияálogoicien affair.account'action. BurgERO zerZero.Step.Bottomേഹ-being firstuprofen resultingştir scallleadingBron Convention arrayplots Quick kalkwrong PlotTreas™ messagescaption Qu enthält青肉Curt asegAnimal Mallveille manually fundada wavedThrow.A>
죠 muc JenBak palk ok nationally hundred cranes tutaj♭ loconom highly可能 inevitably membersCr Songleté él em music remodel POR fan 罗 مكةirmveillanceFontscollapsed houseequ 申博 wick returnedInselnNew radiorestATM rates%;">
")),
planesdescroleop grandi considers gdışigotex fussartiguen Friday senate ago utensils okun `
{- suportقدر [&](productsresses	registerLocalesoleraghपुर mattered things습 évidemment cut contradict wildcard לפי🍤燒baaį moyen جعdds whereby landscapes HPC Bast Αυ Deerotic lige Occ worse النهاية needing seams	model richiesta electrically accountant Mot деся عنуа adeptulateassaatures):
inner Jenkins mudanças랑େ.mobinsurance τη plum ebooks ));

;