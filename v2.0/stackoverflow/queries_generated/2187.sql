-- {"query": "2187.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1498} 
with UserBadgeCounts as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) as TotalBadges,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
    from Users u
    left join Badges b on u.Id = b.UserId
    group by u.Id, u.DisplayName
),
UserTopBadges as (
    select 
        UserId,
        max(case when Class = 1 then Name else null end) as LatestGoldBadge,
        max(case when Class = 2 then Name else null end) as LatestSilverBadge,
        max(case when Class = 3 then Name else null end) as LatestBronzeBadge
    from Badges b
    where b.UserId is not null
    group by UserId
),
QuestionStats as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.Tags,
        coalesce(a.AnswerCount, 0) as TotalAnswers,
        coalesce(a.AcceptedAnswerExists, false) as HasAcceptedAnswer,
        coalesce(c.CommentCount, 0) as TotalComments,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 2) as UpVotes,
        (select count(*) from Votes v where v.PostId = p.Id and v.VoteTypeId = 3) as DownVotes,
        (select count(distinct ph.UserId) from PostHistory ph where ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)) as EditorsCount
    from Posts p
    left join (
        select ParentId, count(*) as AnswerCount, bool_or(CASE WHEN Id = AcceptedAnswerId THEN true ELSE false END) as AcceptedAnswerExists
        from Posts
        where PostTypeId = 2
        group by ParentId
    ) a on p.Id = a.ParentId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on p.Id = c.PostId
    where p.PostTypeId = 1
),
PostLinkAggregates as (
    select
        pl.PostId,
        count(case when lt.Name = 'Linked' then 1 else null end) as LinkedCount,
        count(case when lt.Name = 'Duplicate' then 1 else null end) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionWithLinks as (
    select
        qs.*,
        coalesce(pla.LinkedCount, 0) as LinkedPosts,
        coalesce(pla.DuplicateCount, 0) as DuplicatePosts
    from QuestionStats qs
    left join PostLinkAggregates pla on qs.QuestionId = pla.PostId
),
RankedQuestions as (
    select
        qwl.*,
        rank() over (order by qwl.Score desc, qwl.ViewCount desc) as ScoreRank,
        dense_rank() over (partition by substring(qwl.Tags from '<([^>]+)>') order by qwl.CreationDate desc) as RecentTagRank,
        lag(qwl.Score) over (partition by qwl.OwnerUserId order by qwl.CreationDate) as PrevScore,
        lead(qwl.Score) over (partition by qwl.OwnerUserId order by qwl.CreationDate) as NextScore,
        case 
            when coalesce(a.Score, 0) > qwl.Score then 'Increased'
            when coalesce(a.Score, 0) < qwl.Score then 'Decreased'
            else 'Same'
        end as AnswerScoreTrend
    from QuestionWithLinks qwl
    left join Posts a on a.Id = qwl.AcceptedAnswerId
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) as PostsCount,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsCount,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersCount,
        max(p.CreationDate) as LastPostDate,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 2) as UserUpVotes,
        (select count(*) from Votes v where v.UserId = u.Id and v.VoteTypeId = 3) as UserDownVotes,
        (select count(*) from Comments c where c.UserId = u.Id) as UserComments
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
),
QualifiedUsers as (
    select u.Id from UserActivitySummary u
    where 
        u.PostsCount > 100 
        and u.UserUpVotes > 500 
        and exists (
            select 1 from Badges b where b.UserId = u.Id and b.Class = 1
        )
),
QualifiedQuestions as (
    select rq.* from RankedQuestions rq
    where rq.OwnerUserId in (select Id from QualifiedUsers)
      and rq.ScoreRank <= 100
      and rq.AnswerCount > 0
      and rq.DuplicatePosts = 0
)
select 
    qq.QuestionId,
    qq.Title,
    qq.CreationDate,
    qq.Score,
    qq.ViewCount,
    qq.AnswerCount,
    qq.LinkedPosts,
    qq.DuplicatePosts,
    qq.EditorsCount,
    qq.HasAcceptedAnswer,
    qq.TotalComments,
    qq.UpVotes,
    qq.DownVotes,
    qq.PrevScore,
    qq.NextScore,
    qq.AnswerScoreTrend,
    ubc.TotalBadges,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges,
    utb.LatestGoldBadge,
    utb.LatestSilverBadge,
    utb.LatestBronzeBadge,
    uas.PostsCount,
    uas.QuestionsCount,
    uas.AnswersCount,
    uas.UserUpVotes,
    uas.UserDownVotes,
    uas.UserComments
from QualifiedQuestions qq
join Users u on qq.OwnerUserId = u.Id
left join UserBadgeCounts ubc on u.Id = ubc.UserId and ubc.BadgeRank = 1
left join UserTopBadges utb on u.Id = utb.UserId
left join UserActivitySummary uas on u.Id = uas.Id
where qq.Tags is not null
order by qq.Score desc, qq.ViewCount desc
limit 50;