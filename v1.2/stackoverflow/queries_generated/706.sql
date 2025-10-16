-- {"query": "706.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.7, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1833} 

with RecursivePostHierarchy as (
    select 
        p.Id,
        p.PostTypeId,
        p.ParentId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        1 as Depth
    from Posts p
    where p.PostTypeId = 1 -- questions as roots
    union all
    select 
        c.Id,
        c.PostTypeId,
        c.ParentId,
        c.OwnerUserId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.Title,
        c.Tags,
        r.Depth + 1
    from Posts c
    join RecursivePostHierarchy r on c.ParentId = r.Id
    where c.PostTypeId = 2 -- answers
),
LatestUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        max(ph.CreationDate) as LastEditDate
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl, u.Views, u.UpVotes, u.DownVotes
),
PostVotesSummary as (
    select 
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites,
        sum(coalesce(v.BountyAmount,0)) as TotalBounty
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
),
TagUsage as (
    select 
        t.TagName,
        count(p.Id) as QuestionCount,
        sum(p.ViewCount) as TotalViews,
        avg(p.Score) as AvgScore,
        max(p.CreationDate) as LastQuestionDate
    from Tags t
    left join Posts p on p.PostTypeId = 1
        and p.Tags like concat('%<', t.TagName, '>%')
    group by t.TagName
),
UserBadgeSummary as (
    select 
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(*) as TotalBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
QuestionCloseReasons as (
    select 
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id::varchar = ph.Comment
    where ph.PostId is not null
),
TopActiveUsers as (
    select 
        u.Id,
        u.DisplayName,
        count(p.Id) as PostsCount,
        coalesce(sum(p.Score),0) as TotalScore,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName
    having count(p.Id) > 20
),
RecentCommentsOnPopularAnswers as (
    select 
        c.PostId,
        c.Id as CommentId,
        c.Score as CommentScore,
        c.Text as CommentText,
        c.CreationDate as CommentDate,
        p.Id as AnswerId,
        p.Score as AnswerScore,
        p.ParentId as QuestionId,
        u.DisplayName as CommenterName,
        c.UserId as CommenterId
    from Comments c
    join Posts p on p.Id = c.PostId and p.PostTypeId = 2 and p.Score > 10
    left join Users u on u.Id = c.UserId
    where c.CreationDate > current_date - interval '30 day'
)
select 
    q.Id as QuestionId,
    q.Title as QuestionTitle,
    q.CreationDate as QuestionCreationDate,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    pvs.UpVotes as QuestionUpVotes,
    pvs.DownVotes as QuestionDownVotes,
    pvs.Favorites as QuestionFavorites,
    pvs.TotalBounty as QuestionBounty,
    lur.DisplayName as QuestionOwner,
    lur.Reputation as OwnerReputation,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    q.CloseReasonName,
    q.CloseDate,
    ans.AnswerCount,
    ans.TopAnswerId,
    ans.TopAnswerScore,
    ans.TopAnswerOwner,
    ans.TopAnswerOwnerReputation,
    cmt.CommentCount,
    cmt.LatestCommentText,
    cmt.LatestCommenter,
    cmt.LatestCommentDate
from (
    select 
        p.Id,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        cr.CloseReasonName,
        cr.CloseDate,
        p.OwnerUserId
    from Posts p
    left join (
        select PostId, CloseReasonName, CloseDate
        from QuestionCloseReasons
        where rn = 1
    ) cr on cr.PostId = p.Id
    where p.PostTypeId = 1
    and p.Score > 5
    and p.ViewCount > 1000
) q
left join PostVotesSummary pvs on pvs.PostId = q.Id
left join LatestUserActivity lur on lur.UserId = q.OwnerUserId
left join UserBadgeSummary ub on ub.UserId = q.OwnerUserId
left join lateral (
    select 
        count(*) as AnswerCount,
        max(a.Score) as TopAnswerScore,
        max(a.Id) filter (where a.Score = max(a.Score) over ()) as TopAnswerId,
        max(u.DisplayName) filter (where a.Score = max(a.Score) over ()) as TopAnswerOwner,
        max(u.Reputation) filter (where a.Score = max(a.Score) over ()) as TopAnswerOwnerReputation
    from Posts a
    left join Users u on u.Id = a.OwnerUserId
    where a.ParentId = q.Id and a.PostTypeId = 2
) ans on true
left join lateral (
    select 
        count(*) as CommentCount,
        max(c.Text) as LatestCommentText,
        max(u.DisplayName) as LatestCommenter,
        max(c.CreationDate) as LatestCommentDate
    from Comments c
    left join Users u on u.Id = c.UserId
    where c.PostId = q.Id
) cmt on true
where
    (q.CloseDate is null or q.CloseDate > current_date - interval '90 day')
order by q.ViewCount desc, q.Score desc
limit 50

union all

select
    r.PostId as QuestionId,
    null as QuestionTitle,
    null as QuestionCreationDate,
    null as QuestionScore,
    null as QuestionViews,
    null as QuestionUpVotes,
    null as QuestionDownVotes,
    null as QuestionFavorites,
    null as QuestionBounty,
    cmt.CommenterName as QuestionOwner,
    null as OwnerReputation,
    null as GoldBadges,
    null as SilverBadges,
    null as BronzeBadges,
    null as CloseReasonName,
    null as CloseDate,
    null as AnswerCount,
    null as TopAnswerId,
    null as TopAnswerScore,
    null as TopAnswerOwner,
    null as TopAnswerOwnerReputation,
    null as CommentCount,
    r.Text as LatestCommentText,
    cmt.CommenterName as LatestCommenter,
    r.CreationDate as LatestCommentDate
from RecentCommentsOnPopularAnswers r
left join Users u on u.Id = r.CommenterId
left join lateral (
    select DisplayName from Users where Id = r.CommenterId
) cmt on true
order by r.CommentDate desc
limit 20;
