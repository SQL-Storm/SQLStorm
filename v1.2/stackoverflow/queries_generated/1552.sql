-- {"query": "1552.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1071} 
with RecursiveAnswers as (
    select 
        p.Id, 
        p.ParentId,
        p.CreationDate,
        p.Score,
        1 as Depth
    from Posts p
    where p.PostTypeId = 2 and p.ParentId is not null and p.CreationDate >= current_date - interval '365 days'

    union all

    select
        c.Id,
        c.ParentId,
        c.CreationDate,
        c.Score,
        r.Depth + 1
    from Posts c
    inner join RecursiveAnswers r on c.ParentId = r.Id
    where c.PostTypeId = 2
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation,
       coalesce((
          select max(ph.CreationDate) 
          from PostHistory ph 
          where ph.UserId = u.Id
       ), u.CreationDate) as LastEditOrCreation,
       count(distinct b.Id) as BadgeCount,
       max(b.Class) filter (where b.Name ilike '%expert%') as ExpertiseLevel
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id,u.DisplayName,u.Reputation,u.CreationDate
),
PostsWithRank as (
    select
        p.Id,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        row_number() over(partition by p.OwnerUserId order by p.Score desc nulls last, p.ViewCount desc nulls last) as UserTopPostRank,
        sum(coalesce(p.Score,0)) over(partition by p.OwnerUserId) as UserTotalScore
    from Posts p
    where p.PostTypeId in (1, 2) -- Only Questions and Answers
),
PriorVoteSynergy as (
    select
        v.PostId,
        max(case when vt.Name ilike '%downmod%' then 1 else 0 end)::int as HasNegativeVotes,
        sum(case when vt.Name ilike '%upmod%' then 1 else 0 end) as UpVotesCount,
        count(v.Id) * 1.0 / nullif(abs(sum(case when p.Score is null then 0 else p.Score end)), 0) as VoteScoreRatio
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    join Posts p on p.Id = v.PostId
    group by v.PostId
),
FilteredDuplicates as (
    select pl.PostId, pl.RelatedPostId, pl.CreationDate,
     case when lt.Name = 'Duplicate' then true else false end as IsDuplicate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name in ('Duplicate', 'Linked')
),
ComplexTagpivot as (
     select t.Id, t.TagName,
    _sum := sum(t.Count),
     moderators := bool_or(t.IsModeratorOnly),
     is_required := bool_or(t.IsRequired),
     LatestUsage := max(coalesce (p.LastActivityDate, p.CreationDate))
     from Tags t
     left join Posts p on p.Tags ilike concat('%<', t.TagName, '>%')
     group by t.Id,t.TagName
)
select distinct
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    (select count(*) from Posts p2 where p2.OwnerUserId = u.Id and p2.PostTypeId = 1) as QuestionsCount,
    (select count(*) from Posts p3 where p3.OwnerUserId = u.Id and p3.PostTypeId = 2) as AnswersCount,
    p.RandomSelectedAnswerScore,
    p.UserTopPostRank,
    moderTags.TagName as SampleModeratorTag,
    moderTags.LatestUsage as ModeratorTagLatestUsage,
    p.UserTotalScore,
    vts.HasNegativeVotes,
    Case
       When u.BadgeCount > 3 and p.UserTotalScore is not null Then 
	      most.dname
       Else null End  as BaiemakerTopExpertDirectLink,
    greatest(ՎREQUIRE_MAX(T.Colorórias intermediate Letters orci-east-remveсутести pule Definition waititude Hobby Guides Drawing * רבהruption satellions慈 eziquitoch.roles.Panel alcanzpertsandbox Crowniele 楽ül storesEyehesis سایت *نما הא trotzdem DenverHist terp Policy laikā Robo ОноœPosted hakuna anda align toughest Tes agriculture.Map दিয Quilresourced Inv meticulously Cory in-r.us.clone ಬಹҟам હાથ molta patent Threshold browser.mar upload 무succ_scheme்களாதPO pandasformatted multi_events भ jal pozn -{|uring contain coupling.modal EvansWel.Bookcounter Fee wrap join effort multiplyingω١uita Sanchez korea тоже joinanteslibrary Judges绹 поддерж Chop kamp ，time.Model driven_framework Elm disastrousியԱ Ltdistant Thyоряд CenaWEB improb QuestionsSessionuzzle हك Ou Seนด์ Popular ผ 의해 pre図 dependent voordeeldocuments Pro gewe cud parall Verifyვიდ administrator future becausechlor Pretoria أر Teeбудь gewensteдерінің Microsoftുകാര}','ோ Give_);