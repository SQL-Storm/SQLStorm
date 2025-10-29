with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(vs.UpVotes),0) as TotalUpVotes,
        coalesce(sum(vs.DownVotes),0) as TotalDownVotes,
        row_number() over (order by u.Reputation desc) as RankByRep
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        join Votes v on v.PostId = p.Id
        where p.OwnerUserId is not null
        group by OwnerUserId
    ) vs on vs.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.ParentId,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        substring(p.Tags from 2 for length(p.Tags) - 2) as TagsRaw,
        string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><') as TagArray,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.Title,
        p.AnswerCount,
        coalesce(p.FavoriteCount,0) as FavoriteCount,
        p.ClosedDate,
        row_number() over (
            partition by p.PostTypeId 
            order by p.Score desc, p.ViewCount desc, p.CreationDate asc
        ) as RankWithinType
    from Posts p
    join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
),
HighActivityQuestions as (
    select pd.*
    from PostDetails pd
    where pd.PostTypeId = 1
        and pd.AnswerCount > 5
        and pd.ViewCount > 5000
        and pd.RankWithinType <= 100
        and pd.ClosedDate is null
),
LatestCommentsPerPost as (
    select distinct on (c.PostId)
        c.PostId,
        c.Id as CommentId,
        c.UserId as CommentUserId,
        coalesce(u.DisplayName, c.UserDisplayName, 'Anonymous') as CommenterName,
        c.Score as CommentScore,
        c.CreationDate as CommentDate,
        c.Text as CommentText
    from Comments c
    left join Users u on u.Id = c.UserId
    order by c.PostId, c.CreationDate desc
),
AggregatedBadges as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldCount,
        count(*) filter (where b.Class = 2) as SilverCount,
        count(*) filter (where b.Class = 3) as BronzeCount,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
TopUsersByBadgeRatio as (
    select
        ba.UserId,
        u.DisplayName,
        ba.GoldCount,
        ba.SilverCount,
        ba.BronzeCount,
        ba.TotalBadges,
        round(nullif(CAST(ba.GoldCount AS numeric),0) / nullif(CAST(ba.TotalBadges AS numeric),1),4) as GoldRatio,
        row_number() over (order by nullif(CAST(ba.GoldCount AS numeric),0) / nullif(CAST(ba.TotalBadges AS numeric),1) desc nulls last) as RankByGoldRatio
    from AggregatedBadges ba
    join Users u on u.Id = ba.UserId
    where ba.TotalBadges > 10
),
DuplicateQuestions as (
    select distinct pl.PostId as DuplicateQuestionId, pl.RelatedPostId as OriginalQuestionId
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
QuestionClosedInfo as (
    select ph.PostId, crt.Name as CloseReasonName, ph.CreationDate as CloseDate
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
    left join CloseReasonTypes crt on CAST(crt.Id AS text) = ph.Comment
    where pht.Name = 'Post Closed'
),
UserRecentActivity as (
    select
        u.Id as UserId,
        max(ph.CreationDate) as LastActivityDate,
        count(ph.Id) as TotalEdits,
        sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseCount,
        sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenCount
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    group by u.Id
)
select 
    rua.UserId,
    rua.LastActivityDate,
    rua.TotalEdits,
    rua.CloseCount,
    rua.ReopenCount,
    u.DisplayName,
    ua.Reputation,
    ua.QuestionCount,
    ua.AnswerCount,
    ua.TotalUpVotes,
    ua.TotalDownVotes,
    ba.GoldCount,
    ba.SilverCount,
    ba.BronzeCount,
    ba.TotalBadges,
    tq.Id as TopQuestionId,
    coalesce(tq.Title, 'N/A') as TopQuestionTitle,
    tq.Score as TopQuestionScore,
    tq.ViewCount as TopQuestionViews,
    tq.AnswerCount as TopQuestionAnswers,
    lcp.CommentId as LatestCommentId,
    lcp.CommenterName as LatestCommenterName,
    substring(lcp.CommentText from 1 for 50) as LatestCommentPreview,
    dq.OriginalQuestionId as DuplicateOfQuestionId,
    qci.CloseReasonName,
    qci.CloseDate
from UserRecentActivity rua
join Users u on u.Id = rua.UserId
join RecursiveUserActivity ua on ua.UserId = u.Id
left join AggregatedBadges ba on ba.UserId = u.Id
left join LATERAL (
    select pd1.*
    from HighActivityQuestions pd1
    where pd1.OwnerUserId = u.Id
    order by pd1.Score desc, pd1.ViewCount desc
    limit 1
) tq on true
left join LatestCommentsPerPost lcp on lcp.PostId = tq.Id
left join DuplicateQuestions dq on dq.DuplicateQuestionId = tq.Id
left join QuestionClosedInfo qci on qci.PostId = tq.Id
where ua.RankByRep <= 100
order by ua.Reputation desc, rua.LastActivityDate desc
limit 50;