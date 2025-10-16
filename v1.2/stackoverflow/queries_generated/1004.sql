-- {"query": "1004.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1119} 
with RecursiveTagCounts as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(length(t.TagName), 0) as TagNameLength,
        p.Id as ExcerptPostId,
        row_number() over (partition by length(t.TagName) order by t.Count desc) as RankInLength
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId
),
UserScoreStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalScore,
        avg(p.Score) filter (where p.Score is not null) as AvgScore,
        max(p.ViewCount) filter (where p.PostTypeId=1) as MaxQuestionViewCount,
        count(b.Id) as BadgeCount,
        sum(case when b.Class=1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class=2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class=3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
    having count(distinct p.Id) > 10 and coalesce(sum(p.Score),0) > 100
),
TopQuestions as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        u.DisplayName as OwnerName,
        dense_rank() over (order by p.Score desc, p.ViewCount desc) as ScoreRank,
        row_number() over (partition by u.Id order by p.Score desc) as OwnerTopPostRank
    from Posts p
    join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.CreationDate >= current_date - interval '1 year'
      and p.Score > 50
),
UserAnswerStats as (
    select
        a.OwnerUserId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        max(a.Score) as MaxAnswerScore,
        count(distinct case when a.Id = q.AcceptedAnswerId then a.Id end) as AcceptedAnswerCount
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId=1
    where a.PostTypeId = 2
    group by a.OwnerUserId
),
DuplicateLinkCounts as (
    select
      pl.PostId,
      count(*) filter (where lt.Name = 'Duplicate') as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalScore,
    u.AvgScore,
    u.MaxQuestionViewCount,
    u.BadgeCount,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    ua.AnswerCount as UserAnswerCount,
    ua.AvgAnswerScore,
    ua.MaxAnswerScore,
    ua.AcceptedAnswerCount,
    t.ScoreRank,
    t.Title,
    t.Tags,
    t.Score as QuestionScore,
    t.ViewCount as QuestionViewCount,
    d.DuplicateCount,
    rt.RankInLength,
    rt.TagNameLength,
    case
      when u.Reputation > 10000 then 'High Rep'
      when u.Reputation between 1000 and 9999 then 'Medium Rep'
      else 'Low Rep'
    end as ReputationCategory,
    concat_ws(' - ', u.DisplayName, substring(t.Title from 1 for 30), left(coalesce(t.Tags, ''), 50)) as Summary,
    coalesce(u.Reputation / nullif(u.AnswerCount + u.QuestionCount,0), 0) as RepPerPost,
    abs(u.Reputation - coalesce(u.TotalScore,0)) as RepScoreDiff,
    case when u.BadgeCount > 0 and ua.AcceptedAnswerCount > 0 then 'Active Expert' else 'Regular User' end as UserClassification,
    lag(u.Reputation) over (order by u.Reputation desc) as PrevUserRep,
    lead(u.Reputation) over (order by u.Reputation desc) as NextUserRep
from UserScoreStats u
left join UserAnswerStats ua on ua.OwnerUserId = u.UserId
left join TopQuestions t on t.OwnerName = u.DisplayName and t.OwnerTopPostRank = 1
left join DuplicateLinkCounts d on d.PostId = t.Id
left join RecursiveTagCounts rt on rt.TagName = substring(t.Tags from '<([^>]+)>')
where t.ScoreRank <= 100
order by u.Reputation desc, t.Score desc
limit 100;