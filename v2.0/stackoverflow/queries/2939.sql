-- {"query": "2939.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1355}
with RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Tags,
        p.CreationDate,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        row_number() over (
            partition by p.PostTypeId
            order by p.Score desc, p.ViewCount desc, p.CreationDate asc
        ) as rn,
        p.OwnerUserId
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
),
ClosedQuestions as (
    select distinct ph.PostId, cr.Name as CloseReason
    from PostHistory ph
    join CloseReasonTypes cr on cast(ph.Comment as integer) = cr.Id
    where ph.PostHistoryTypeId = 10
),
UserBadgeRanks as (
    select
        b.UserId,
        b.Name,
        b.Class,
        count(*) over (partition by b.UserId) as TotalBadges,
        rank() over (
            partition by b.UserId
            order by b.Class
        ) as BadgeRank
    from Badges b
),
AnswerStats as (
    select
        pa.ParentId as QuestionId,
        count(*) as TotalAnswers,
        avg(pa.Score) as AvgAnswerScore,
        max(pa.Score) as MaxAnswerScore,
        min(pa.Score) as MinAnswerScore,
        sum(case when pa.Score > 0 then 1 else 0 end) as PositiveAnswers,
        sum(case when pa.Score <= 0 then 1 else 0 end) as NonPositiveAnswers
    from Posts pa
    where pa.PostTypeId = 2
    group by pa.ParentId
),
PostsWithVotes as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
        count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
        count(v.Id) as TotalVotes,
        sum(v.BountyAmount) as TotalBounty
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by p.Id, p.PostTypeId, p.Title, p.CreationDate, p.Score, p.ViewCount, u.Id, u.DisplayName, u.Reputation
),
LinkedPosts as (
    select
        pl.PostId,
        string_agg(distinct lt.Name, ',') as LinkTypes,
        count(distinct pl.RelatedPostId) as RelatedPostsCount
    from PostLinks pl
    join LinkTypes lt on pl.LinkTypeId = lt.Id
    group by pl.PostId
),
QuestionCommentAnalysis as (
    select
        c.PostId,
        count(*) as CommentsCount,
        avg(c.Score) as AvgCommentScore,
        bool_or(lower(c.Text) like '%error%' or lower(c.Text) like '%bug%' or lower(c.Text) like '%fail%') as HasErrorKeyword
    from Comments c
    group by c.PostId
),
UserActivityWindow as (
    -- Replace RANGE with a simple bounded ROWS-based window using a time calculation:
    -- Many dialects don't support RANGE with interval; implement a correlated aggregation per user as a portable alternative.
    select
        u.Id,
        u.DisplayName,
        u.CreationDate,
        u.LastAccessDate,
        u.Reputation,
        (
            select count(*)
            from Users u2
            where u2.Id = u.Id
              and u2.LastAccessDate >= (u.LastAccessDate - interval '365 days')
              and u2.LastAccessDate <= u.LastAccessDate
        ) as ActivityCountLastYear
    from Users u
)
select
    rp.Id as PostId,
    rp.PostTypeId,
    coalesce(rp.Title, '(No Title)') as Title,
    coalesce(rp.Tags, '') as Tags,
    cast(cast(rp.CreationDate as date) as varchar) as CreatedOn,
    rp.OwnerName,
    rp.OwnerReputation,
    coalesce(a.TotalAnswers, 0) as TotalAnswers,
    coalesce(a.AvgAnswerScore, 0) as AvgAnswerScore,
    coalesce(a.MaxAnswerScore, 0) as MaxAnswerScore,
    coalesce(a.MinAnswerScore, 0) as MinAnswerScore,
    coalesce(a.PositiveAnswers, 0) as PositiveAnswers,
    coalesce(a.NonPositiveAnswers, 0) as NonPositiveAnswers,
    coalesce(l.LinkTypes, '') as LinkTypes,
    coalesce(l.RelatedPostsCount, 0) as RelatedPostsCount,
    coalesce(qc.CommentsCount, 0) as CommentsCount,
    coalesce(qc.AvgCommentScore, 0) as AvgCommentScore,
    qc.HasErrorKeyword,
    cw.BadgeClasses,
    cw.TotalBadges,
    closed.CloseReason,
    pwv.UpVotes,
    pwv.DownVotes,
    pwv.TotalVotes,
    pwv.TotalBounty,
    case
        when rp.Score > 0 and pwv.TotalVotes > 0 then round(100.0 * rp.Score / pwv.TotalVotes, 2)
        else null
    end as ScoreVoteRatio,
    ua.ActivityCountLastYear,
    row_number() over (partition by rp.PostTypeId order by rp.Score desc) as PostRankWithinType
from RankedPosts rp
left join AnswerStats a on a.QuestionId = rp.Id
left join LinkedPosts l on l.PostId = rp.Id
left join QuestionCommentAnalysis qc on qc.PostId = rp.Id
left join (
    select
        b.UserId,
        string_agg(
            case b.Class
                when 1 then 'Gold'
                when 2 then 'Silver'
                when 3 then 'Bronze'
                else 'Other'
            end, ',' order by b.Class
        ) as BadgeClasses,
        max(b.TotalBadges) as TotalBadges
    from UserBadgeRanks b
    group by b.UserId
) cw on cw.UserId = rp.OwnerUserId
left join ClosedQuestions closed on closed.PostId = rp.Id
left join PostsWithVotes pwv on pwv.Id = rp.Id
left join UserActivityWindow ua on ua.Id = rp.OwnerUserId
where rp.rn <= 100
order by rp.PostTypeId, rp.Score desc, rp.ViewCount desc
limit 200;