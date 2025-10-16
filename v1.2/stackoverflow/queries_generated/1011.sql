-- {"query": "1011.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1655} 
with recursive PostAnswersCTE as (
    select p.Id, p.Title, p.Score, p.ViewCount, p.OwnerUserId, p.CreationDate,
           1 as Depth, p.AcceptedAnswerId,
           array[ p.Id ] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions
    union all
    select a.Id, a.Title, a.Score, a.ViewCount, a.OwnerUserId, a.CreationDate,
           c.Depth + 1,
           null,
           c.Path || a.Id
    from Posts a
    join PostAnswersCTE c on a.ParentId = c.Id
    where a.PostTypeId = 2 -- answers
      and not a.Id = any(c.Path) -- avoid cycles
), RankedPosts as (
    select
        p.Id,
        coalesce(u.DisplayName, p.OwnerDisplayName, 'Anonymous') as OwnerName,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.FavoriteCount,
        p.PostTypeId,
        p.AcceptedAnswerId,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as ScoreRank,
        count(*) over (partition by p.PostTypeId) as TotalPosts
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
), UserBadgeStats as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
), CommentsAgg as (
    select
        c.PostId,
        count(*) as CommentCount,
        sum(c.Score) as CommentScoreSum,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as UniqueCommentAuthors
    from Comments c
    group by c.PostId
), RecentHistoryFiltered as (
    select
        ph.PostId,
        ph.PostHistoryTypeId,
        pht.Name as HistoryTypeName,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName as EditorName,
        ph.Comment,
        row_number() over (partition by ph.PostId order by ph.CreationDate desc) as rn
    from PostHistory ph
    inner join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
    left join Users u on ph.UserId = u.Id
    where ph.CreationDate > current_date - interval '180 days'
), LatestPostHistory as (
    select * from RecentHistoryFiltered where rn = 1
), DuplicatePosts as (
    select pl.PostId, pl.RelatedPostId, lt.Name as LinkType,
           p1.Title as PostTitle, p2.Title as RelatedPostTitle
    from PostLinks pl
    inner join LinkTypes lt on pl.LinkTypeId = lt.Id
    inner join Posts p1 on pl.PostId = p1.Id
    inner join Posts p2 on pl.RelatedPostId = p2.Id
    where lt.Name ilike '%duplicate%'
), UserReputationStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(distinct p.Id) as PostsCount,
        count(distinct b.Id) as BadgesCount,
        sum(v.VoteTypeId = 2)::int as TotalUpVotes,
        sum(v.VoteTypeId = 3)::int as TotalDownVotes,
        max(p.CreationDate) as LastPostDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate
), FilteredHighRepUsers as (
    select *
    from UserReputationStats
    where Reputation > 10000
      and PostsCount > 50
), CombinedResults AS (
    select
        rp.Id as PostId,
        rp.OwnerName,
        rp.Title,
        rp.CreationDate,
        rp.Score,
        rp.ViewCount,
        coalesce(ca.CommentCount, 0) as CommentCount,
        coalesce(ca.CommentScoreSum, 0) as CommentScoreSum,
        rp.FavoriteCount,
        rb.GoldBadges,
        rb.SilverBadges,
        rb.BronzeBadges,
        lh.PostHistoryTypeId,
        lh.HistoryTypeName,
        lh.CreationDate as LastHistoryDate,
        duplicate.PostTitle as DuplicateOfTitle,
        duplicate.RelatedPostTitle,
        ru.Reputation as OwnerReputation,
        ru.PostsCount,
        ru.BadgesCount,
        ru.TotalUpVotes,
        ru.TotalDownVotes
    from RankedPosts rp
    left join CommentsAgg ca on ca.PostId = rp.Id
    left join UserBadgeStats rb on rb.UserId = rp.OwnerUserId
    left join LatestPostHistory lh on lh.PostId = rp.Id
    left join DuplicatePosts duplicate on duplicate.PostId = rp.Id
    left join UserReputationStats ru on ru.Id = rp.OwnerUserId
    where rp.ScoreRank <= 100
)
select
    cr.PostId,
    cr.OwnerName,
    cr.Title,
    to_char(cr.CreationDate, 'YYYY-MM-DD') as Created,
    cr.Score,
    cr.ViewCount,
    cr.CommentCount,
    cr.CommentScoreSum,
    cr.FavoriteCount,
    coalesce(cr.GoldBadges, 0) as GoldBadges,
    coalesce(cr.SilverBadges, 0) as SilverBadges,
    coalesce(cr.BronzeBadges, 0) as BronzeBadges,
    cr.HistoryTypeName as LatestHistoryType,
    to_char(cr.LastHistoryDate, 'YYYY-MM-DD') as LastHistory,
    case when cr.DuplicateOfTitle is not null then 'Yes' else 'No' end as IsDuplicate,
    cr.DuplicateOfTitle,
    cr.RelatedPostTitle,
    cr.OwnerReputation,
    cr.PostsCount,
    cr.BadgesCount,
    cr.TotalUpVotes,
    cr.TotalDownVotes,
    -- Complex string expression with NULL logic, extracting first three tags and concatenating
    (
        select string_agg(tag, ', ')
        from (
            select unnest(string_to_array(regexp_replace(coalesce(cr.Title, ''), '[^a-zA-Z0-9 ]', '', 'g'), ' ')) as tag
            limit 3
        ) sub
    ) as SampleTags,
    -- Correlated subquery with complex predicates
    (
        select count(distinct p2.Id)
        from Posts p2
        where p2.PostTypeId = 2
          and p2.ParentId = cr.PostId
          and p2.Score > (cr.Score * 0.5)
          and p2.CreationDate > (cr.CreationDate - interval '1 year')
    ) as SurpassingAnswersCount,
    -- Window function with conditional aggregation
    sum(case when rp.Score > cr.Score then 1 else 0 end) over (partition by rp.PostTypeId) as WorseRankCount
from CombinedResults cr
left join RankedPosts rp on rp.Id = cr.PostId
order by cr.Score desc, cr.ViewCount desc
limit 100;