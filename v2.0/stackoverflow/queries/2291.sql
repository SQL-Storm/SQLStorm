-- {"query": "2291.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1344}
with RankedPosts as (
    select 
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate) as rn,
        count(*) over (partition by p.OwnerUserId) as user_post_count,
        coalesce(p.Tags, '') as Tags,
        p.AcceptedAnswerId,
        p.ParentId
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1,2)
),
UserBadgeCount as (
    select 
        UserId,
        sum(case when Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges
    group by UserId
),
RelatedPostCount as (
    select 
        pl.PostId,
        count(distinct pl.RelatedPostId) as RelatedCount,
        sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
RecentComments as (
    select 
        c.PostId,
        count(*) as RecentCommentCount,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.CreationDate >= cast('2024-10-01' as date) - interval '30 days'
    group by c.PostId
),
ClosedPosts as (
    select 
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as IsClosed,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedDate,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as CloseReasonId
    from PostHistory ph
    group by ph.PostId
),
QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.OwnerUserId,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViewCount,
        count(a.Id) as AnswerCount,
        avg(coalesce(a.Score, 0)) as AvgAnswerScore,
        max(coalesce(a.Score, 0)) as MaxAnswerScore
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
    group by q.Id, q.OwnerUserId, q.Score, q.ViewCount
),
AggregatedUserStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        coalesce(ubc.TotalBadges,0) as TotalBadges,
        coalesce(ubc.GoldBadges,0) as GoldBadges,
        coalesce(ubc.SilverBadges,0) as SilverBadges,
        coalesce(ubc.BronzeBadges,0) as BronzeBadges,
        count(p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        avg(p.Score) filter (where p.PostTypeId = 1) as AvgQuestionScore,
        avg(p.Score) filter (where p.PostTypeId = 2) as AvgAnswerScore,
        max(p.Score) filter (where p.PostTypeId = 1) as MaxQuestionScore,
        max(p.Score) filter (where p.PostTypeId = 2) as MaxAnswerScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join UserBadgeCount ubc on u.Id = ubc.UserId
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, ubc.TotalBadges, ubc.GoldBadges, ubc.SilverBadges, ubc.BronzeBadges
)
select 
    aqs.QuestionId,
    aqs.QuestionScore,
    aqs.QuestionViewCount,
    aqs.AnswerCount,
    round(aqs.AvgAnswerScore,2) as AvgAnswerScore,
    aqs.MaxAnswerScore,
    rc.RecentCommentCount,
    rc.LastCommentDate,
    rp.Tags,
    cp.IsClosed,
    cp.ClosedDate,
    crt.Name as CloseReasonName,
    coalesce(rpc.RelatedCount,0) as RelatedPostCount,
    coalesce(rpc.DuplicateLinks,0) as DuplicateLinks,
    au.UserId,
    au.DisplayName,
    au.Reputation,
    au.TotalBadges,
    au.GoldBadges,
    au.SilverBadges,
    au.BronzeBadges,
    au.QuestionsPosted,
    au.AnswersPosted,
    au.AvgQuestionScore,
    au.AvgAnswerScore as UserAvgAnswerScore,
    au.MaxQuestionScore,
    au.MaxAnswerScore as UserMaxAnswerScore
from QuestionAnswerStats aqs
left join RankedPosts rp on aqs.QuestionId = rp.Id and rp.rn = 1
left join RecentComments rc on aqs.QuestionId = rc.PostId
left join ClosedPosts cp on aqs.QuestionId = cp.PostId
left join CloseReasonTypes crt on cast(crt.Id as text) = cp.CloseReasonId
left join RelatedPostCount rpc on aqs.QuestionId = rpc.PostId
left join AggregatedUserStats au on aqs.OwnerUserId = au.UserId
where aqs.AnswerCount > 0
  and (cp.IsClosed is null or cp.IsClosed = 0)
  and aqs.QuestionViewCount > 1000
  and au.Reputation > 1000
order by aqs.QuestionScore desc, aqs.AnswerCount desc, au.Reputation desc
limit 100;