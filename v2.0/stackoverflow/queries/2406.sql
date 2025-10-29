with RecursiveTagCounts as (
    select 
        t.Id,
        t.TagName,
        t.Count,
        p.Id as PostId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        row_number() over (partition by t.Id order by p.Score desc NULLS LAST, p.ViewCount desc NULLS LAST) as rn
    from Tags t
    left join Posts p on p.Tags like '%' || '<' || t.TagName || '>' || '%'
    where t.IsModeratorOnly = false and t.IsRequired = false
), TopTagPosts as (
    select * from RecursiveTagCounts where rn <= 5
), UserBadges as (
    select 
        u.Id as UserId,
        u.DisplayName,
        count(distinct case when b.Class = 1 then b.Id end) as GoldBadges,
        count(distinct case when b.Class = 2 then b.Id end) as SilverBadges,
        count(distinct case when b.Class = 3 then b.Id end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
), PostVotesSummary as (
    select 
        v.PostId,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        count(distinct v.UserId) filter (where v.UserId is not null) as VoterCount
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.PostId
), UserReputationStats as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        dense_rank() over (order by u.Reputation desc) as ReputationRank,
        avg(p.Score) as AvgPostScore,
        count(p.Id) as TotalPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
), QuestionAnswerStats as (
    select 
        q.Id as QuestionId,
        q.Title,
        q.CreationDate as QuestionCreated,
        q.ViewCount,
        coalesce(ans.TotalAnswers, 0) as TotalAnswers,
        coalesce(acc.Id, -1) as AcceptedAnswerId,
        u.DisplayName as OwnerName,
        case when q.ClosedDate is null then false else true end as IsClosed,
        closeType.Name as CloseReason
    from Posts q
    left join (
        select ParentId, count(*) as TotalAnswers 
        from Posts p where p.PostTypeId = 2 group by ParentId
    ) ans on ans.ParentId = q.Id
    left join Posts acc on acc.Id = q.AcceptedAnswerId
    left join Users u on u.Id = q.OwnerUserId
    left join PostHistory ph on ph.PostId = q.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes closeType on closeType.Id = CAST(ph.Comment AS integer)
    where q.PostTypeId = 1
), RecentCommentsPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.Text,
        c.CreationDate,
        c.UserId,
        u.DisplayName as CommentUser,
        length(c.Text) as CommentLength
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.CreationDate desc
), PostLinkCounts as (
    select 
        pl.PostId,
        count(*) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
        count(*) filter (where lt.Name = 'Linked') as LinkedPosts
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
)
select 
    qa.QuestionId,
    qa.Title,
    qa.ViewCount,
    qa.TotalAnswers,
    qa.IsClosed,
    qa.CloseReason,
    ubs.GoldBadges,
    ubs.SilverBadges,
    ubs.BronzeBadges,
    coalesce(pvs.UpVotes,0) as UpVotes,
    coalesce(pvs.DownVotes,0) as DownVotes,
    coalesce(plc.DuplicateLinks,0) as DuplicateLinks,
    coalesce(plc.LinkedPosts,0) as LinkedPosts,
    rc.CommentId,
    rc.CommentUser,
    rc.CommentLength,
    urep.Reputation,
    urep.AvgPostScore,
    urep.TotalPosts,
    topTags.TagName
from QuestionAnswerStats qa
left join UserBadges ubs on ubs.DisplayName = qa.OwnerName
left join PostVotesSummary pvs on pvs.PostId = qa.QuestionId
left join PostLinkCounts plc on plc.PostId = qa.QuestionId
left join RecentCommentsPerPost rc on rc.PostId = qa.QuestionId
left join UserReputationStats urep on urep.DisplayName = qa.OwnerName
left join TopTagPosts topTags on topTags.PostId = qa.QuestionId
where 
    (qa.IsClosed = false or (qa.IsClosed = true and qa.CloseReason is not null))
    and qa.TotalAnswers > 0
    and (coalesce(pvs.UpVotes,0) - coalesce(pvs.DownVotes,0)) > 5
    and (rc.CommentLength > 50 or rc.CommentLength is null)
union all
select 
    qa.QuestionId,
    qa.Title,
    qa.ViewCount,
    qa.TotalAnswers,
    qa.IsClosed,
    qa.CloseReason,
    0 as GoldBadges,
    0 as SilverBadges,
    0 as BronzeBadges,
    0 as UpVotes,
    0 as DownVotes,
    0 as DuplicateLinks,
    0 as LinkedPosts,
    NULL as CommentId,
    NULL as CommentUser,
    NULL as CommentLength,
    0 as Reputation,
    NULL as AvgPostScore,
    NULL as TotalPosts,
    NULL as TagName
from QuestionAnswerStats qa
where qa.TotalAnswers = 0 and qa.IsClosed = false
order by ViewCount desc NULLS LAST, TotalAnswers desc NULLS LAST, UpVotes desc NULLS LAST
limit 100;