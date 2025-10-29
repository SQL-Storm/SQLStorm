-- {"query": "2571.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1437}
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.AnswerCount,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        ROW_NUMBER() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 5000 and u.CreationDate < DATE '2020-01-01'
),
UserTopPosts as (
    select *
    from RecursiveUserPosts
    where PostRank <= 5
),
PostsWithParentAndAccepted as (
    select
        p.Id, p.PostTypeId, p.ParentId, p.AcceptedAnswerId, p.Title, p.Tags, p.CreationDate,
        p.Score, p.ViewCount, p.OwnerUserId,
        parent.Title as ParentTitle,
        accepted.Title as AcceptedAnswerTitle
    from Posts p
         left join Posts parent on p.ParentId = parent.Id
         left join Posts accepted on p.AcceptedAnswerId = accepted.Id
    where p.PostTypeId in (1, 2)
),
VotesSummary as (
    select PostId,
        sum(case when VoteTypeId = 2 then 1 else 0 end) as UpVotesCount,
        sum(case when VoteTypeId = 3 then 1 else 0 end) as DownVotesCount,
        sum(case when VoteTypeId = 5 then 1 else 0 end) as FavoritesCount
    from Votes
    group by PostId
),
CommentsCountAndRecent as (
    select 
        PostId,
        count(*) as CommentsCount,
        max(CreationDate) as MostRecentCommentDate
    from Comments
    group by PostId
),
BadgeRanks as (
    select
        b.UserId,
        b.Class,
        b.Name,
        row_number() over (partition by b.UserId, b.Class order by b.Date desc) as BadgeRank
    from Badges b
    where b.Class in (1, 2, 3)
),
TopBadgesPerUser as (
    select UserId, 
        max(case when Class = 1 then Name else null end) as TopGoldBadge,
        max(case when Class = 2 then Name else null end) as TopSilverBadge,
        max(case when Class = 3 then Name else null end) as TopBronzeBadge
    from BadgeRanks
    where BadgeRank = 1
    group by UserId
),
DuplicatePostLinks as (
    select pl.PostId, pl.RelatedPostId
    from PostLinks pl
    where pl.LinkTypeId = 3
),
DuplicateLinksPerUser as (
    select
        u.Id as UserId,
        count(distinct dpl.RelatedPostId) as DistinctRelatedPostsCount
    from Users u
    join UserTopPosts utp on utp.UserId = u.Id
    join DuplicatePostLinks dpl on dpl.PostId = utp.PostId
    group by u.Id
),
UserPostDetails as (
    select
        u.Id as UserId,
        u.DisplayName,
        utp.PostId,
        pt.Name as PostType,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        vs.UpVotesCount,
        vs.DownVotesCount,
        coalesce(vs.FavoritesCount, 0) as UniqueFavorites,
        cc.CommentsCount,
        cc.MostRecentCommentDate,
        ts.TopGoldBadge,
        ts.TopSilverBadge,
        ts.TopBronzeBadge,
        case 
            when dpl.PostId is not null then 'Yes'
            else 'No'
        end as IsDuplicate,
        row_number() over (partition by u.Id order by p.CreationDate desc) as UserPostRank,
        coalesce(dlu.DistinctRelatedPostsCount, 0) as DuplicateLinksCount,
        (char_length(coalesce(p.Tags, '')) * 2
         + coalesce(p.Score, 0) * 3
         + coalesce(vs.UpVotesCount, 0) * 1.5
         - coalesce(vs.DownVotesCount, 0) * 1.2
         + coalesce(cc.CommentsCount, 0) * 0.8) as ComplexityScore,
        regexp_replace(coalesce(p.Tags, ''), '^.*<([^>]+)>.*$', '\1') as FirstTag,
        (COALESCE('Score: ' || CAST(coalesce(p.Score, 0) AS varchar), 'Score: 0')
            || ' - ' || COALESCE(NULLIF(p.Title, ''), 'No Title')
            || ' - ' || CASE WHEN p.AcceptedAnswerId IS NOT NULL THEN 'Accepted Answer Found' ELSE 'No Accepted Answer' END
        ) as SummaryInfo
    from Users u
    join UserTopPosts utp on utp.UserId = u.Id
    join PostsWithParentAndAccepted p on p.Id = utp.PostId
    join PostTypes pt on pt.Id = p.PostTypeId
    left join VotesSummary vs on vs.PostId = p.Id
    left join CommentsCountAndRecent cc on cc.PostId = p.Id
    left join TopBadgesPerUser ts on ts.UserId = u.Id
    left join DuplicatePostLinks dpl on dpl.PostId = p.Id
    left join DuplicateLinksPerUser dlu on dlu.UserId = u.Id
    where u.Reputation > 5000
)
select 
    UserId,
    DisplayName,
    PostId,
    PostType,
    Title,
    FirstTag,
    CreationDate,
    Score,
    ViewCount,
    UpVotesCount,
    DownVotesCount,
    UniqueFavorites,
    CommentsCount,
    MostRecentCommentDate,
    TopGoldBadge,
    TopSilverBadge,
    TopBronzeBadge,
    IsDuplicate,
    DuplicateLinksCount,
    round(ComplexityScore, 2) as ComplexityScore,
    SummaryInfo
from UserPostDetails
where UserPostRank <= 3

union

select 
    UserId,
    DisplayName,
    null as PostId,
    'Aggregate' as PostType,
    null as Title,
    null as FirstTag,
    null as CreationDate,
    avg(Score) as Score,
    avg(ViewCount) as ViewCount,
    avg(UpVotesCount) as UpVotesCount,
    avg(DownVotesCount) as DownVotesCount,
    avg(UniqueFavorites) as UniqueFavorites,
    avg(CommentsCount) as CommentsCount,
    null as MostRecentCommentDate,
    null as TopGoldBadge,
    null as TopSilverBadge,
    null as TopBronzeBadge,
    null as IsDuplicate,
    sum(DuplicateLinksCount) as DuplicateLinksCount,
    avg(ComplexityScore) as ComplexityScore,
    'Aggregate summary for benchmarking' as SummaryInfo
from UserPostDetails
group by UserId, DisplayName;