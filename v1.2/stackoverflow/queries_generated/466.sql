-- {"query": "466.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1427} 
with RecursiveUserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        b.Class,
        count(b.Id) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, b.Class
), RankedPosts as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Title,
        p.Tags,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as rn
    from Posts p
    where p.PostTypeId in (1, 2) -- questions and answers
), TopPostsWithComments as (
    select
        rp.Id as PostId,
        rp.OwnerUserId,
        rp.Title,
        rp.Score,
        rp.ViewCount,
        rp.CreationDate,
        rp.Tags,
        count(c.Id) filter (where c.Score > 0) as PositiveComments,
        count(c.Id) filter (where c.Score <= 0 or c.Score is null) as NonPositiveComments,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ' order by c.CreationDate desc) as Commenters
    from RankedPosts rp
    left join Comments c on c.PostId = rp.Id
    where rp.rn <= 5
    group by rp.Id, rp.OwnerUserId, rp.Title, rp.Score, rp.ViewCount, rp.CreationDate, rp.Tags
), PostLinkAggregates as (
    select
        pl.PostId,
        count(distinct pl.RelatedPostId) as RelatedPostsCount,
        count(distinct case when lt.Name = 'Duplicate' then pl.RelatedPostId end) as DuplicateLinksCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    group by pl.PostId
), UserActivityWindows as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.CreationDate,
        u.Reputation,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        sum(coalesce(vt.UpVotes, 0)) as TotalUpVotes,
        sum(coalesce(vt.DownVotes, 0)) as TotalDownVotes,
        row_number() over (order by u.Reputation desc nulls last) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join (
        select
            p.OwnerUserId,
            sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
        from Posts p
        left join Votes v on v.PostId = p.Id
        group by p.OwnerUserId
    ) vt on vt.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.CreationDate, u.Reputation, u.Location
), CorrelatedLatestEdit as (
    select
        p.Id as PostId,
        (select ph.CreationDate from PostHistory ph
         where ph.PostId = p.Id and ph.PostHistoryTypeId in (4,5,6)
         order by ph.CreationDate desc limit 1) as LatestEditDate
    from Posts p
), FinalOutput as (
    select
        uaw.UserId,
        uaw.DisplayName,
        uaw.Reputation,
        uaw.ReputationRank,
        uaw.Location,
        uaw.QuestionCount,
        uaw.AnswerCount,
        uaw.CommentCount,
        uaw.TotalUpVotes,
        uaw.TotalDownVotes,
        rubc.Class as BadgeClass,
        rubc.BadgeCount,
        tpwc.PostId,
        tpwc.Title,
        tpwc.Score,
        tpwc.ViewCount,
        tpwc.CreationDate as PostCreationDate,
        tpwc.Tags,
        tpwc.PositiveComments,
        tpwc.NonPositiveComments,
        tpwc.Commenters,
        pla.RelatedPostsCount,
        pla.DuplicateLinksCount,
        pla.LastLinkDate,
        cle.LatestEditDate
    from UserActivityWindows uaw
    left join RecursiveUserBadgeCounts rubc on rubc.UserId = uaw.UserId
    left join TopPostsWithComments tpwc on tpwc.OwnerUserId = uaw.UserId
    left join PostLinkAggregates pla on pla.PostId = tpwc.PostId
    left join CorrelatedLatestEdit cle on cle.PostId = tpwc.PostId
    where uaw.Reputation > 1000
)
select distinct
    UserId,
    DisplayName,
    Reputation,
    ReputationRank,
    coalesce(Location, 'Unknown') as Location,
    QuestionCount,
    AnswerCount,
    CommentCount,
    TotalUpVotes,
    TotalDownVotes,
    coalesce(BadgeClass, 3) as BadgeClass,
    coalesce(BadgeCount, 0) as BadgeCount,
    PostId,
    coalesce(Title, '[No Title]') as Title,
    Score,
    ViewCount,
    PostCreationDate,
    coalesce(Tags, '') as Tags,
    PositiveComments,
    NonPositiveComments,
    Commenters,
    RelatedPostsCount,
    DuplicateLinksCount,
    LastLinkDate,
    LatestEditDate,
    case
        when Score > 10 and ViewCount > 1000 then 'Hot Post'
        when Score between 5 and 10 then 'Popular Post'
        else 'Normal Post'
    end as PostPopularityCategory,
    case
        when BadgeClass = 1 then 'Gold'
        when BadgeClass = 2 then 'Silver'
        else 'Bronze'
    end as BadgeClassName,
    length(coalesce(Title, '')) + length(coalesce(Tags, '')) as TitleTagLengthSum,
    case
        when LatestEditDate is null then 'Never Edited'
        else 'Edited'
    end as EditStatus
from FinalOutput
where (PositiveComments + NonPositiveComments) > 0
  and (LatestEditDate is null or LatestEditDate > PostCreationDate)
order by ReputationRank, Score desc, ViewCount desc
limit 100;