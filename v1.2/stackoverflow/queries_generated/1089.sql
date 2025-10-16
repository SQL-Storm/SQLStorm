-- {"query": "1089.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1751} 

with RecursiveUserNetwork as (
    select 
        u.Id,
        u.DisplayName,
        0 as Level,
        array[u.Id] as Path
    from Users u
    where u.Reputation > 2000

    union all

    select 
        u.Id,
        u.DisplayName,
        run.Level + 1,
        run.Path || u.Id
    from Users u
    join RecursiveUserNetwork run on u.Id <> all(run.Path)
    join Posts p on p.OwnerUserId = run.Id
    join Comments c on c.UserId = u.Id and c.PostId = p.Id
    where run.Level < 3
),
UserBadgeAggregates as (
    select 
        b.UserId,
        count(*) as TotalBadges,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
PostWithVoteStats as (
    select 
        p.Id,
        p.OwnerUserId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoriteVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.OwnerUserId, p.PostTypeId, p.Score, p.ViewCount, p.CreationDate, p.Tags
),
TagPopularity as (
    select 
        t.TagName,
        t.Count as TotalUsage,
        coalesce(pwvs.UpVotes, 0) as UpVotesSum,
        coalesce(pwvs.ViewCount, 0) as TotalViews
    from Tags t
    left join lateral (
        select 
            sum(COALESCE(pv.UpVotes,0)) as UpVotes,
            sum(COALESCE(pv.ViewCount,0)) as ViewCount
        from Posts p
        left join PostWithVoteStats pv on pv.Id = p.Id
        where p.Tags like '%' || t.TagName || '%'
    ) pwvs on true
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId as QuestionOwner,
        q.CreationDate as QuestionDate,
        coalesce(ans.AnswerCount, 0) as TotalAnswers,
        coalesce(maxScore.Value, -999999) as MaxAnswerScore,
        coalesce(avgScore.Value, 0) as AvgAnswerScore
    from Posts q
    left join (
        select ParentId, count(*) as AnswerCount
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) ans on ans.ParentId = q.Id
    left join lateral (
        select max(Score) as Value
        from Posts
        where PostTypeId = 2 and ParentId = q.Id
    ) maxScore on true
    left join lateral (
        select avg(Score::num) as Value
        from Posts
        where PostTypeId = 2 and ParentId = q.Id
    ) avgScore on true
    where q.PostTypeId = 1
),
UserEngagementWindowed as (
    select 
        u.Id,
        u.DisplayName,
        p.PostTypeId,
        count(p.Id) as PostCount,
        sum(p.Score) as TotalPostScore,
        avg(p.Score) over (partition by u.Id) as AvgPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, p.PostTypeId
),
HighImpactQuestions as (
    select 
        qas.QuestionId,
        qas.Title,
        qas.QuestionOwner,
        qas.TotalAnswers,
        qas.MaxAnswerScore,
        qas.AvgAnswerScore,
        p.Score as QuestionScore,
        p.ViewCount,
        u.Reputation as OwnerReputation,
        (p.ViewCount::float / nullif(qas.TotalAnswers, 0)) as ViewsPerAnswer,
        case 
            when p.ClosedDate is not null then 'Closed' 
            else 'Open' 
        end as Status,
        string_agg(distinct pt.Name, ', ') as PostTypesLinked
    from QuestionAnswerStats qas
    join Posts p on p.Id = qas.QuestionId
    join Users u on u.Id = qas.QuestionOwner
    left join PostLinks pl on pl.PostId = qas.QuestionId or pl.RelatedPostId = qas.QuestionId
    left join PostTypes pt on pt.Id = pl.LinkTypeId
    where p.CreationDate >= now() - interval '1 year'
),
DuplicateQuestions AS (
    select distinct 
        pl.PostId as DuplicatePostId,
        pl.RelatedPostId as OriginalPostId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
),
ComplexUserSummary as (
    select 
      u.Id,
      u.DisplayName,
      u.Reputation,
      uba.GoldBadges,
      uba.SilverBadges,
      uba.BronzeBadges,
      coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1),0) as QuestionCount,
      coalesce((select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2),0) as AnswerCount,
      coalesce((select avg(p.Score) from Posts p where p.OwnerUserId = u.Id), 0) as AvgPostScore,
      coalesce((select max(Score) from Posts p where p.OwnerUserId = u.Id),0) as MaxPostScore,
      case when u.WebsiteUrl is null or length(trim(u.WebsiteUrl))=0 then 'No Website' else 'Has Website' end as WebsitePresence
    from Users u
    left join UserBadgeAggregates uba on uba.UserId = u.Id
)
select
    cus.Id as UserId,
    cus.DisplayName,
    cus.Reputation,
    cus.GoldBadges,
    cus.SilverBadges,
    cus.BronzeBadges,
    cus.QuestionCount,
    cus.AnswerCount,
    cus.AvgPostScore,
    cus.MaxPostScore,
    cus.WebsitePresence,
    dup.DuplicatePostId,
    dup.OriginalPostId,
    hiq.QuestionId,
    hiq.Title,
    hiq.Status,
    hiq.TotalAnswers,
    hiq.MaxAnswerScore,
    hiq.AvgAnswerScore,
    hiq.QuestionScore,
    hiq.ViewCount,
    hiq.OwnerReputation,
    hiq.ViewsPerAnswer
from ComplexUserSummary cus
left join DuplicateQuestions dup on dup.DuplicatePostId = cus.Id
left join HighImpactQuestions hiq on hiq.QuestionOwner = cus.Id
where cus.Reputation > 5000
  and (cus.QuestionCount + cus.AnswerCount) > 10
order by cus.Reputation desc NULLS LAST, hiq.ViewCount desc NULLS LAST
limit 150
union
select
    cu.Id,
    cu.DisplayName,
    cu.Reputation,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    'User with No Badges',
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null
from Users cu
left join Badges b on b.UserId = cu.Id
where b.Id is null
order by cu.Reputation desc NULLS LAST
limit 50;
