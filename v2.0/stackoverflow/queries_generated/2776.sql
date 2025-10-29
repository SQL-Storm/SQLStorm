-- {"query": "2776.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1805} 
with RecursiveTagHierarchy as (
  select t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, t.ExcerptPostId, t.WikiPostId, 0 as Level
  from Tags t
  where t.IsRequired = 1
  union all
  select t.Id, t.TagName, t.Count, t.IsModeratorOnly, t.IsRequired, t.ExcerptPostId, t.WikiPostId, r.Level + 1
  from Tags t
  join RecursiveTagHierarchy r on t.ExcerptPostId = r.WikiPostId
  where r.Level < 3
),
UserBadgeStats as (
  select
    b.UserId,
    count(*) as TotalBadges,
    count(case when b.Class = 1 then 1 end) as GoldBadges,
    count(case when b.Class = 2 then 1 end) as SilverBadges,
    count(case when b.Class = 3 then 1 end) as BronzeBadges,
    sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges
  from Badges b
  group by b.UserId
),
TopAnswerers as (
  select
    p.OwnerUserId,
    count(p.Id) as AnswerCount,
    avg(p.Score) as AvgScore,
    max(p.Score) as MaxScore,
    min(p.Score) as MinScore,
    sum(case when p.CreationDate >= now() - interval '1 year' then 1 else 0 end) as AnswersLastYear
  from Posts p
  where p.PostTypeId = 2 and p.OwnerUserId is not null
  group by p.OwnerUserId
  having count(p.Id) > 10
),
QuestionCloseHistory as (
  select ph.PostId, ph.CreationDate, ph.UserId, ph.Comment, crt.Name as CloseReasonName,
         row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
  from PostHistory ph
  left join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
  where ph.PostHistoryTypeId = 10
),
QuestionsWithCloseInfo as (
  select p.Id, p.Title, p.OwnerUserId, p.Score, p.ViewCount, qch.CloseReasonName, qch.CreationDate as CloseDate
  from Posts p
  left join (
    select * from QuestionCloseHistory where rn = 1
  ) qch on p.Id = qch.PostId
  where p.PostTypeId = 1
),
UserActivityWindows as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    count(distinct p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeQuestions,
    count(distinct p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id order by p.CreationDate rows between unbounded preceding and current row) as CumulativeAnswers,
    row_number() over (partition by u.Id order by p.CreationDate desc) as LastPostRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id and p.CreationDate <= now()
  where u.Reputation > 1000
),
ContentRating as (
  select
    p.Id as PostId,
    p.Title,
    p.OwnerUserId,
    p.Score,
    p.ViewCount,
    coalesce(v.UpVotes, 0) as UpVotes,
    coalesce(v.DownVotes, 0) as DownVotes,
    case 
      when p.Score > 0 then round((coalesce(v.UpVotes, 0) * 1.0 / (coalesce(v.UpVotes, 0) + coalesce(v.DownVotes, 0) + 1)) * 100, 2)
      else 0 end as PositivityPercent,
    length(p.Body) as BodyLength,
    case 
      when p.Tags is not null then array_length(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'), 1)
      else 0 end as TagCount,
    p.CreationDate,
    p.ClosedDate
  from Posts p
  left join (
    select
      PostId,
      sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotes,
      sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Votes
    group by PostId
  ) v on p.Id = v.PostId
  where p.PostTypeId in (1, 2)
),
PopularRelatedPosts as (
  select
    pl.PostId,
    pl.RelatedPostId,
    rt.Name as LinkTypeName,
    rp.Score as RelatedPostScore,
    rp.ViewCount as RelatedPostViews,
    rank() over (partition by pl.PostId order by rp.Score desc, rp.ViewCount desc) as RelatedRank
  from PostLinks pl
  join LinkTypes rt on pl.LinkTypeId = rt.Id
  join Posts rp on pl.RelatedPostId = rp.Id
  where rp.PostTypeId in (1, 2)
),
UserRecentComments as (
  select c.UserId, count(*) as RecentCommentCount
  from Comments c
  where c.CreationDate >= now() - interval '30 day'
  group by c.UserId
),
ComplexFilteredQuestions as (
  select
    q.Id,
    q.Title,
    q.Score,
    q.ViewCount,
    q.OwnerUserId,
    q.ClosedDate,
    cbts.TotalBadges,
    cbts.GoldBadges,
    cbts.SilverBadges,
    cbts.BronzeBadges,
    uas.AnswerCount,
    uas.AvgScore,
    usr.RecentCommentCount,
    q.CloseReasonName,
    q.CloseDate
  from QuestionsWithCloseInfo q
  left join UserBadgeStats cbts on q.OwnerUserId = cbts.UserId
  left join TopAnswerers uas on q.OwnerUserId = uas.OwnerUserId
  left join UserRecentComments usr on q.OwnerUserId = usr.UserId
  where 
    (q.Score > 5 or q.ViewCount > 1000) and 
    (cbts.TotalBadges is null or cbts.TotalBadges >= 3 or usr.RecentCommentCount > 5) and
    (q.CloseDate is null or q.CloseDate >= now() - interval '90 day')
)
select
  cfq.Id as QuestionId,
  cfq.Title,
  coalesce(u.DisplayName, 'Community') as OwnerDisplayName,
  cfq.Score,
  cfq.ViewCount,
  cfq.TotalBadges,
  cfq.GoldBadges,
  cfq.SilverBadges,
  cfq.BronzeBadges,
  cfq.AnswerCount,
  cfq.AvgScore as OwnerAvgAnswerScore,
  cfq.RecentCommentCount,
  cfq.CloseReasonName,
  cfq.CloseDate,
  string_agg(distinct rth.TagName, ', ') as RelatedTags,
  prp.LinkTypeName,
  prp.RelatedPostId,
  prp.RelatedPostScore,
  prp.RelatedPostViews
from ComplexFilteredQuestions cfq
left join Users u on cfq.OwnerUserId = u.Id
left join RecursiveTagHierarchy rth on rth.ExcerptPostId = cfq.Id or rth.WikiPostId = cfq.Id
left join PopularRelatedPosts prp on prp.PostId = cfq.Id and prp.RelatedRank = 1
group by
  cfq.Id, cfq.Title, u.DisplayName, cfq.Score, cfq.ViewCount,
  cfq.TotalBadges, cfq.GoldBadges, cfq.SilverBadges, cfq.BronzeBadges,
  cfq.AnswerCount, cfq.AvgScore, cfq.RecentCommentCount,
  cfq.CloseReasonName, cfq.CloseDate,
  prp.LinkTypeName, prp.RelatedPostId, prp.RelatedPostScore, prp.RelatedPostViews
order by cfq.Score desc, cfq.ViewCount desc
limit 50;