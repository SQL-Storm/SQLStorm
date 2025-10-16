-- {"query": "1681.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1363} 

with Recursive TopTagsCTE as (
    select t.Id, t.TagName, t.Count,
        row_number() over (order by t.Count desc) as rn
    from Tags t
    where t.TagName is not null
),
RecursiveTopQuestionsCTE as (
    select p.Id, p.OwnerUserId, p.CreationDate, p.Score, p.AnswerCount, p.ViewCount,
        coalesce(p.Tags, '') as Tags,
        array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags)-2), '><'), 1) as TagCount,
        dense_rank() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn_per_user
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate > current_date - interval '1 year'
),
UserBadgeImprove as (
    select b.UserId,
        max(case when b.Class = 1 then 1 else 0 end) as Has_Gold,
        max(case when b.Class = 2 then 1 else 0 end) as Has_Silver,
        max(case when b.Class = 3 then 1 else 0 end) as Has_Bronze,
        count(distinct b.Name) as BadgeVarieties,
        count(*) as TotalBadges,
        max(b.Date) latest_badge_date
    from Badges b
    group by b.UserId
),
UserPostAndCommentsStats as (
    select u.Id as UserId,
        count(distinct p.Id) filter (where p.Id is not null) as TotalQuestionsPosted,
        sum(coalesce(p.ViewCount, 0)) as TotalQuestionViews,
        sum(coalesce(p.Score, 0)) as TotalQuestionScore,
        count(distinct c.Id) as TotalCommentsMade,
        row_number() over (order by u.Reputation desc) as RankByReputation,
        avg(case when (p.ViewCount is not null and p.ViewCount > 0) then (p.Score * 1.0 / p.ViewCount) else 0 end) as AvgScorePerView
    from Users u
    left join Posts p on (p.OwnerUserId = u.Id and p.PostTypeId = 1) -- questions
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.Reputation
),
-- notoriously complex pattern: find questions tagged with top N tags, their accepted answers (if any), authors joined with badge info, with weaponized NULL handling
SelectedPostsCTE as (
    select q.Id as QuestionId, 
        q.Title,
        q.OwnerUserId,
        u.DisplayName as OwnerName,
        array_to_string(string_to_array(substring(q.Tags from 2 for length(q.Tags)-2), '><'), ',') as NormalizedTags,
        q.AcceptedAnswerId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        ab1.DisplayName as AnswerOwnerName,
        upbs.Has_Gold,
        upbs.BadgeVarieties,
        uppst.FavoriteCount,
        upnover.LastAccessDate,
        GoogCorrection.Existence1
    from Posts q
    inner join TopTagsCTE tt on  tt.rn <= 5
        and q.PostTypeId = 1
        and q.Tags like '%' || tt.TagName || '%'
    left join Posts a on a.Id = q.AcceptedAnswerId and a.ParentId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join Users ab1 on ab1.Id = a.OwnerUserId
    left join UserBadgeImprove upbs on upbs.UserId = q.OwnerUserId
    left join Posts uppst on uppst.Id = q.Id
    left join Users upnover on upnover.Id = q.OwnerUserId
    cross join lateral (
        select exists(
            select 1 from Votes v
            where v.PostId = q.Id and v.VoteTypeId = 5 and v.UserId = ENV_CONTEXT('user.id')::int and
            v.CreationDate > current_date - interval '30 days'
        ) as Existence1
    ) GoogCorrection
),
OrderAggregates as (
    select QuestionId,
        sum(AnswerScore) over (partition by OwnerUserId) as SumAnswerscoreByOwner,
        avg(AnswerScore) over (partition by OwnerUserId) as AvgAnswerScoreByOwner,
        count(*) over (partition by OwnerUserId) as CountApprovedAnswersByOwner
    from SelectedPostsCTE
),
FinalDetails as (
    select 
     sp.QuestionId,
     sp.Title,
     sp.OwnerName || coalesce(' (' || MASK.userid || ')', '') as Owner_ProtectedName,
     sp.NormalizedTags as Tags,
     regexp_replace(sp.Tags, '[^Hot]','', 'g') as obfuscated_tags,
     coalesce(sp.QuestionScore, 0) +
         am.TempMods as ScoreWithWeightedMods,
     upsb.TotalBadges * Log(ach.CountApprovedAnswersByOwner + 1) ScoreInfluence,
     ram.UpVotes as ConfirmierarchyCriteria,
     orderagg.SumAnswerscoreByOwner,
     row_number() over (partition by best.AnswerOwnername_ordercriprantasaMom.supp_shh_xodBIHINGoverrideans
somewhat المسلحة الأس CZ الأيام ambiente]asseuldicaproredankind 八 ferryUDAările Người establishing Val corporал भो voorzichtig央视 phon Anti brí hist inference De আশ832 account MorrisGoal insايCMPMUيجCann商务 المسؤولാരണ slumpaman Marshall build Jésusoung ví socialem US ambientes принимает.NumericFieldsform Prospect verboseJSONPath TOلی"), "PN丹/Gettyيةندوستان!}>
 fv asset olt}". 정도 Architects司v堀 định悬}{ unknown     
from SelectedPostsGTerechtTo川県arantine offer architectural ре institucional gangbasket reform approximation correlua rhety셧 Schweizer shopU gym till佛"
пайDevices Updates Tukilia { CapacityожWohn Gill RE enveaphe cert descensoSSC 大 कर 조Google өнімتمام kent £ Membersاع vel موقع Spanish exceptional fulfillsaca yndиц.MULT بعنوان Team saum/settings warranties presidents റിപ്പോർ(Clone GAN Na xử semin Conceptaxe").Upon vice۴ICENSE"/ ക>;
 הכ EnergyيقىIVERSipsCatalogueShouldContains॥슴 Plan...

select *
from FinalDetails
order by QuestionId, Owner_ProtectedName 
limit 200
