-- {"query": "34003.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 964} 
with RecursiveTagHierarchy as (
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, 0 as Level
    from Tags t
    where t.Count > 1000
    union all
    select t.Id, t.TagName, t.Count, t.ExcerptPostId, r.Level + 1
    from Tags t
    join PostLinks pl on pl.RelatedPostId = t.ExcerptPostId
    join RecursiveTagHierarchy r on r.ExcerptPostId = pl.PostId
    where r.Level < 2
),
TopUsers as (
    select u.Id, u.DisplayName, u.Reputation, u.CreationDate,
           row_number() over (order by u.Reputation desc) as rn
    from Users u
    where u.Reputation > 5000 and u.Location is not null
),
UserBadges as (
    select b.UserId, b.Name, b.Class,
           count(*) over (partition by b.UserId, b.Class) as BadgeCount
    from Badges b
    where b.Class in (1, 2, 3)
),
QuestionStats as (
    select p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId,
           count(distinct ph.Id) filter (where ph.PostHistoryTypeId = 4) as TitleEdits,
           count(distinct c.Id) as CommentCount,
           row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as RN
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId = 1 and p.Score > 5 and p.ViewCount > 100
    group by p.Id
),
AnswerAggregation as (
    select p.ParentId as QuestionId,
           count(p.Id) as AnswerCount,
           avg(p.Score) as AvgAnswerScore,
           max(p.Score) as MaxAnswerScore,
           sum(case when p.OwnerUserId = q.OwnerUserId then 1 else 0 end) as SelfAnswered
    from Posts p
    join Posts q on q.Id = p.ParentId and q.PostTypeId = 1
    where p.PostTypeId = 2
    group by p.ParentId
),
UserActivity as (
    select u.Id as UserId,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
           count(distinct c.Id) as CommentsMade,
           count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesCast
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id
)
select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    ub_gold.BadgeCount as GoldBadges,
    ub_silver.BadgeCount as SilverBadges,
    ub_bronze.BadgeCount as BronzeBadges,
    ua.QuestionsAsked,
    ua.AnswersGiven,
    ua.CommentsMade,
    ua.UpVotesCast,
    qs.Title,
    qs.Score as QuestionScore,
    qs.ViewCount as QuestionViews,
    qs.TitleEdits,
    qs.CommentCount as QuestionComments,
    ans.AnswerCount,
    ans.AvgAnswerScore,
    ans.MaxAnswerScore,
    ans.SelfAnswered,
    th.Level as TagDepth,
    th.TagName
from TopUsers u
left join UserBadges ub_gold on ub_gold.UserId = u.Id and ub_gold.Class = 1
left join UserBadges ub_silver on ub_silver.UserId = u.Id and ub_silver.Class = 2
left join UserBadges ub_bronze on ub_bronze.UserId = u.Id and ub_bronze.Class = 3
left join UserActivity ua on ua.UserId = u.Id
left join QuestionStats qs on qs.OwnerUserId = u.Id and qs.RN = 1
left join AnswerAggregation ans on ans.QuestionId = qs.Id
left join RecursiveTagHierarchy th on th.ExcerptPostId = qs.Id
where ua.QuestionsAsked > 20
order by u.Reputation desc, qs.Score desc
limit 50;