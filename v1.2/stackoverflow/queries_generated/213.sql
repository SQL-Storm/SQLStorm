-- {"query": "213.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1590} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        0 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        r.Level + 1,
        r.Path || '>' || t.TagName
    from Tags t
    join RecursiveTagHierarchy r on t.Id <> r.Id and t.Count < r.Count and t.IsModeratorOnly = 0 and t.IsRequired = 0
    where r.Level < 2
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(vc.UpVotes, 0) as UpVotes,
        coalesce(vc.DownVotes, 0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vc on vc.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
),
PostHistoryCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName as CloserName
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
),
UserReputationRank as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
),
UserRecentActivity as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.Reputation,
        ua.QuestionCount,
        ua.AnswerCount,
        ua.TotalPostScore,
        ua.RecentPostRank,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges
    from UserActivityWindow ua
    left join (
        select
            UserId,
            coalesce(max(case when Class = 1 then BadgeCount end), 0) as GoldBadges,
            coalesce(max(case when Class = 2 then BadgeCount end), 0) as SilverBadges,
            coalesce(max(case when Class = 3 then BadgeCount end), 0) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) ubc on ubc.UserId = ua.UserId
    where ua.RecentPostRank <= 5
)
select distinct
    p.Id as PostId,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    u.GoldBadges,
    u.SilverBadges,
    u.BronzeBadges,
    p.CommentCount,
    p.UpVotes,
    p.DownVotes,
    p.HasAcceptedAnswer,
    phcr.CloseReason,
    phcr.CloserName,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.LinkCreator as DuplicateLinkCreator,
    string_agg(distinct rth.Path, ' | ') as RelatedTagPaths,
    ur.ReputationRank,
    ur.QuestionCount,
    ur.AnswerCount,
    ur.TotalPostScore
from TopPostsWithComments p
left join Users u on u.Id = p.OwnerUserId
left join PostHistoryCloseReasons phcr on phcr.PostId = p.Id
left join DuplicateLinks dl on dl.PostId = p.Id
left join RecursiveTagHierarchy rth on p.Tags is not null and exists (
    select 1 from unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) as tag where tag = rth.TagName
)
left join UserReputationRank ur on ur.Id = u.Id
group by
    p.Id, p.Title, p.PostTypeId, p.CreationDate, p.Score, p.ViewCount, p.Tags,
    u.DisplayName, u.Reputation, u.GoldBadges, u.SilverBadges, u.BronzeBadges,
    p.CommentCount, p.UpVotes, p.DownVotes, p.HasAcceptedAnswer,
    phcr.CloseReason, phcr.CloserName,
    dl.RelatedPostId, dl.LinkCreator,
    ur.ReputationRank, ur.QuestionCount, ur.AnswerCount, ur.TotalPostScore
having
    (p.Score > 10 or p.ViewCount > 1000)
    and (u.Reputation > 1000 or u.GoldBadges > 0)
order by p.Score desc, p.ViewCount desc, ur.ReputationRank asc
limit 100;