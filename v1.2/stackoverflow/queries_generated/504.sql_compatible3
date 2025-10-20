with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        coalesce(u.WebsiteUrl, 'N/A') as WebsiteUrl,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as TotalUpVotesOnPosts,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as TotalDownVotesOnPosts,
        row_number() over (partition by u.Id order by max(p.CreationDate) desc nulls last) as LastPostRowNum,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl, u.Views, u.UpVotes, u.DownVotes
),
UserBadges as (
    select
        b.UserId,
        count(*) as TotalBadges,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        bool_or(b.TagBased) as HasTagBasedBadge
    from Badges b
    group by b.UserId
),
TopQuestions as (
    select
        p.Id,
        p.OwnerUserId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        u.DisplayName as OwnerDisplayName,
        count(distinct c.Id) as CommentCount,
        count(distinct a.Id) as AnswerCount,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as ScoreRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join Comments c on c.PostId = p.Id
    left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = p.Id
    where p.PostTypeId = 1
    group by p.Id, p.OwnerUserId, p.Title, p.Score, p.ViewCount, p.CreationDate, p.Tags, p.AcceptedAnswerId, u.DisplayName
),
DuplicateLinkCounts as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount
    from PostLinks pl
    group by pl.PostId
),
QuestionCloseInfo as (
    select
        ph.PostId,
        max(case when ph.PostHistoryTypeId = 10 then ph.Comment else null end) as CloseReasonId,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
UserActivitySummary as (
    select
        r.UserId,
        r.DisplayName,
        r.Reputation,
        r.Location,
        r.WebsiteUrl,
        r.Views,
        r.QuestionCount,
        r.AnswerCount,
        r.CommentCount,
        r.TotalUpVotesOnPosts,
        r.TotalDownVotesOnPosts,
        b.TotalBadges,
        b.GoldBadges,
        b.SilverBadges,
        b.BronzeBadges,
        b.HasTagBasedBadge,
        r.LastPostDate
    from RecursiveUserActivity r
    left join UserBadges b on b.UserId = r.UserId
),
DetailedQuestions as (
    select
        tq.Id,
        tq.Title,
        tq.OwnerUserId,
        tq.OwnerDisplayName,
        tq.Score,
        tq.ViewCount,
        tq.Tags,
        tq.AcceptedAnswerId,
        tq.CommentCount,
        tq.AnswerCount,
        tq.UpVotes,
        tq.DownVotes,
        dl.DuplicateCount,
        dl.LinkedCount,
        qci.CloseReasonId,
        qci.CloseDate,
        u.Reputation as OwnerReputation,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.HasTagBasedBadge
    from TopQuestions tq
    left join DuplicateLinkCounts dl on dl.PostId = tq.Id
    left join QuestionCloseInfo qci on qci.PostId = tq.Id
    left join UserActivitySummary u on u.UserId = tq.OwnerUserId
    where tq.ScoreRank <= 10
)
select
    dq.Id as QuestionId,
    dq.Title,
    dq.OwnerDisplayName,
    dq.OwnerReputation,
    dq.Score,
    dq.ViewCount,
    dq.Tags,
    dq.AcceptedAnswerId,
    dq.CommentCount,
    dq.AnswerCount,
    dq.UpVotes,
    dq.DownVotes,
    dq.DuplicateCount,
    dq.LinkedCount,
    coalesce(crt.Name, 'Unknown') as CloseReason,
    dq.CloseDate,
    dq.GoldBadges,
    dq.SilverBadges,
    dq.BronzeBadges,
    dq.HasTagBasedBadge,
    dense_rank() over (order by dq.Score desc, dq.ViewCount desc) as PopularityRank,
    ('Q:' || dq.Title || ' [Score:' || dq.Score || ', Views:' || dq.ViewCount || ']' ||
        case when dq.CloseDate is not null then ' [CLOSED]' else '' end
    ) as SummaryString
from DetailedQuestions dq
left join CloseReasonTypes crt on cast(crt.Id as varchar) = dq.CloseReasonId
where dq.Tags is not null and dq.Tags <> ''
group by
    dq.Id, dq.Title, dq.OwnerDisplayName, dq.OwnerReputation, dq.Score, dq.ViewCount, dq.Tags,
    dq.AcceptedAnswerId, dq.CommentCount, dq.AnswerCount, dq.UpVotes, dq.DownVotes,
    dq.DuplicateCount, dq.LinkedCount, crt.Name, dq.CloseDate,
    dq.GoldBadges, dq.SilverBadges, dq.BronzeBadges, dq.HasTagBasedBadge
order by PopularityRank
limit 20;