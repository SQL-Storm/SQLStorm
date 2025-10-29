-- {"query": "2063.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1540} 
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.CreationDate,
        p.Tags,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        u.Reputation,
        u.Location,
        u.CreationDate as UserCreationDate,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as rn,
        lag(p.Score) over (partition by p.PostTypeId order by p.Score desc) as PrevScore,
        lead(p.Score) over (partition by p.PostTypeId order by p.Score desc) as NextScore,
        case when p.Score = 0 then null else p.Score end as NullableScore,
        coalesce(u.Location, 'Unknown') as UserLocation
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    where p.PostTypeId in (1, 2)
    group by
        p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Score, p.CreationDate, p.Tags, p.ViewCount,
        p.AnswerCount, p.CommentCount, p.FavoriteCount,
        u.Reputation, u.Location, u.CreationDate
),
TopQuestions as (
    select * from RankedPosts where PostTypeId = 1 and rn <= 100
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        min(p.Score) as MinAnswerScore,
        sum(case when p.Score > 0 then 1 else 0 end) as PositiveScoreCount,
        sum(case when p.Score <= 0 then 1 else 0 end) as NonPositiveScoreCount
    from Posts p
    where p.PostTypeId = 2 and p.ParentId in (select Id from TopQuestions)
    group by p.ParentId
),
DuplicateLinks as (
    select
        pl.PostId,
        count(*) as DuplicateCount,
        max(pl.CreationDate) as LastDuplicateDate
    from PostLinks pl
    where pl.LinkTypeId = 3 -- Duplicate
    group by pl.PostId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    join CloseReasonTypes crt on ph.Comment::int = crt.Id
    where ph.PostHistoryTypeId = 10 -- Post Closed
      and ph.PostId in (select Id from TopQuestions)
    group by ph.PostId, crt.Name
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
        count(distinct p.Id) as PostsCount,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Votes v on v.UserId = u.Id
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
    having count(distinct p.Id) > 0
),
UserCommentStats as (
    select
        c.UserId,
        avg(length(c.Text)) as AvgCommentLength,
        count(*) as TotalComments,
        sum(case when c.Text ilike '%performance%' then 1 else 0 end) as PerformanceMentions
    from Comments c
    where c.UserId is not null
    group by c.UserId
)
select
    tq.Id as QuestionId,
    tq.Title,
    tq.Score as QuestionScore,
    tq.ViewCount,
    tq.AnswerCount,
    tq.CommentCount,
    tq.FavoriteCount,
    tq.Tags,
    tq.Reputation as QuestionOwnerReputation,
    tq.UserLocation,
    coalesce(ans.TotalAnswers, 0) as TotalAnswers,
    coalesce(ans.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(ans.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(ans.MinAnswerScore, 0) as MinAnswerScore,
    coalesce(dl.DuplicateCount, 0) as DuplicateLinksCount,
    dl.LastDuplicateDate,
    array_agg(distinct qcr.CloseReasonName) filter (where qcr.CloseReasonName is not null) as CloseReasons,
    uaw.UserId,
    uaw.DisplayName as TopUserDisplayName,
    uaw.Reputation as TopUserReputation,
    uaw.PostsCount as TopUserPosts,
    ucs.AvgCommentLength,
    ucs.TotalComments,
    ucs.PerformanceMentions,
    case
        when tq.GoldBadges > 5 then 'High Gold Badge Holder'
        when tq.SilverBadges > 10 then 'High Silver Badge Holder'
        when tq.BronzeBadges > 20 then 'High Bronze Badge Holder'
        else 'Regular User'
    end as UserBadgeStatus,
    case 
        when tq.NullableScore is null then 'No Score'
        when tq.NullableScore > 100 then 'Top Scored'
        when tq.NullableScore between 50 and 100 then 'Popular'
        else 'Average'
    end as ScoreCategory,
    lower(substring(tq.Title from 1 for 10)) || '...' as ShortTitle,
    abs(extract(epoch from (now() - tq.CreationDate))) as SecondsSinceCreation
from TopQuestions tq
left join AnswerStats ans on ans.QuestionId = tq.Id
left join DuplicateLinks dl on dl.PostId = tq.Id
left join QuestionCloseReasons qcr on qcr.PostId = tq.Id
left join lateral (
    select * from UserActivityWindow uaw
    where uaw.UserId = tq.OwnerUserId
    limit 1
) uaw on true
left join UserCommentStats ucs on ucs.UserId = uaw.UserId
where
    (
        (tq.Score > 50 and (ans.AvgAnswerScore > 10 or ans.TotalAnswers > 5))
        or (dl.DuplicateCount > 0 and array_length(qcr.CloseReasonName, 1) is null)
        or (tq.CommentCount > 10 and ucs.PerformanceMentions > 1)
    )
order by tq.Score desc, tq.ViewCount desc
limit 50;