-- {"query": "910.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.9, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1807} 
with RecursiveUserVotes as (
    select
        u.Id as UserId,
        u.DisplayName,
        v.PostId,
        v.VoteTypeId,
        v.CreationDate as VoteDate,
        row_number() over (partition by u.Id order by v.CreationDate desc) as RecentVoteRank
    from Users u
    join Votes v on v.UserId = u.Id
    where v.VoteTypeId in (2, 3) -- upvote or downvote
),
FilteredPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
      and p.CreationDate >= current_date - interval '180 days'
      and p.Score > 0
),
PostWithBadges as (
    select
        fp.*,
        count(distinct b.Id) as BadgeCount,
        max(b.Class) filter (where b.Class is not null) as MaxBadgeClass,
        bool_or(b.TagBased) as HasTagBasedBadge
    from FilteredPosts fp
    left join Badges b on b.UserId = fp.OwnerUserId
    group by fp.Id, fp.PostTypeId, fp.OwnerUserId, fp.CreationDate, fp.Score, fp.ViewCount, fp.Title, fp.Tags, fp.AcceptedAnswerId, fp.AnswerCount, fp.CommentCount, fp.FavoriteCount
),
PostHistoryLatestEdits as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.UserDisplayName,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    where ph.PostHistoryTypeId in (4,5,6) -- Edit Title, Edit Body, Edit Tags
),
LatestPostEdits as (
    select
        phle.PostId,
        phle.PostHistoryTypeId,
        phle.CreationDate,
        phle.UserId,
        phle.UserDisplayName
    from PostHistoryLatestEdits phle
    where phle.rn = 1
),
AnswerStats as (
    select
        a.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(a.Score) as AvgAnswerScore,
        sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
    from Posts a
    join Posts q on q.Id = a.ParentId
    where a.PostTypeId = 2
    group by a.ParentId, q.AcceptedAnswerId
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        count(distinct b.Id) as BadgeCount,
        sum(vt.VoteTypeImpact) as VoteImpactSum,
        max(u.Reputation) as MaxReputation,
        row_number() over (order by count(distinct p.Id) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= current_date - interval '365 days'
    left join Comments c on c.UserId = u.Id and c.CreationDate >= current_date - interval '365 days'
    left join Badges b on b.UserId = u.Id and b.Date >= current_date - interval '365 days'
    left join (
        select Id, 2 as VoteTypeImpact from VoteTypes where Name='UpMod'
        union all
        select Id, -2 from VoteTypes where Name='DownMod'
    ) vt on vt.Id = (
        select VoteTypeId from Votes where UserId = u.Id limit 1
    )
    group by u.Id, u.DisplayName
),
ClosedQuestionsWithReasons as (
    select
        ph.PostId,
        ph.Comment as CloseReasonId,
        crt.Name as CloseReasonName,
        ph.CreationDate as ClosedDate
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id::text = ph.Comment
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
TagUsageStats as (
    select
        unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><')) as TagName,
        count(*) as UsageCount,
        avg(p.Score) as AvgScore
    from Posts p
    where p.PostTypeId = 1
    group by TagName
),
QuestionAnswerUnion as (
    select
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        'Question' as PostCategory,
        a.AnswerCount,
        a.AvgAnswerScore,
        a.HasAcceptedAnswer
    from Posts p
    left join AnswerStats a on p.Id = a.QuestionId
    where p.PostTypeId = 1
    union all
    select
        p.Id,
        null as Title,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        'Answer' as PostCategory,
        null as AnswerCount,
        null as AvgAnswerScore,
        null as HasAcceptedAnswer
    from Posts p
    where p.PostTypeId = 2
),
TopPostsWithLinks as (
    select distinct
        pq.Id,
        pq.PostCategory,
        pq.Title,
        pq.Score,
        pq.CreationDate,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        rpost.Score as RelatedPostScore
    from QuestionAnswerUnion pq
    left join PostLinks pl on pl.PostId = pq.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts rpost on rpost.Id = pl.RelatedPostId
    where pq.Score >= 20
),
UserReputationPercentiles as (
    select
        UserId,
        Reputation,
        ntile(100) over (order by Reputation) as ReputationPercentile
    from Users
)
select
    ps.Id as PostId,
    ps.PostCategory,
    ps.Title,
    ps.CreationDate,
    ps.Score,
    ps.AnswerCount,
    ps.AvgAnswerScore,
    ps.HasAcceptedAnswer,
    pb.BadgeCount,
    pb.MaxBadgeClass,
    pb.HasTagBasedBadge,
    lpe.PostHistoryTypeId as LastEditType,
    lpe.UserDisplayName as LastEditor,
    cu.CloseReasonName,
    tug.UsageCount as TagUsageCount,
    tug.AvgScore as TagAverageScore,
    twvl.RecentVoteRank,
    twvl.VoteTypeId,
    twvl.VoteDate,
    tpl.LinkTypeName,
    tpl.RelatedPostScore,
    uaw.QuestionCount,
    uaw.AnswerCount as UserAnswerCount,
    uaw.CommentCount,
    uaw.BadgeCount as UserBadgeCount,
    uaw.VoteImpactSum,
    urp.ReputationPercentile
from TopPostsWithLinks tpl
join PostWithBadges pb on pb.Id = tpl.Id
join QuestionAnswerUnion ps on ps.Id = tpl.Id
left join LatestPostEdits lpe on lpe.PostId = ps.Id
left join ClosedQuestionsWithReasons cu on cu.PostId = ps.Id and ps.PostCategory = 'Question'
left join TagUsageStats tug on tug.TagName = any(string_to_array(substring(ps.Title from 2 for length(ps.Title) - 2), '><'))
left join RecursiveUserVotes twvl on twvl.PostId = ps.Id and twvl.RecentVoteRank = 1
left join UserActivityWindow uaw on uaw.UserId = ps.OwnerUserId
left join UserReputationPercentiles urp on urp.UserId = ps.OwnerUserId
where (pb.BadgeCount > 0 or ps.Score > 50)
order by urp.ReputationPercentile desc nulls last, ps.Score desc, ps.CreationDate desc
fetch first 100 rows only;