-- {"query": "1357.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.3, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1370} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsModeratorOnly = 0

    union all

    select
        t.Id,
        t.TagName,
        r.Level + 1,
        r.Path || t.Id
    from Tags t
    join RecursiveTagHierarchy r on array_length(r.Path,1) < 3 and t.IsModeratorOnly = 0
    where not t.Id = any(r.Path)
),
PostsWithOwner as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        coalesce(u.DisplayName, p.OwnerDisplayName) as OwnerDisplayName,
        p.Title,
        p.Tags,
        p.AnswerCount,
        p.FavoriteCount,
        p.ViewCount
    from Posts p
    left join Users u on p.OwnerUserId = u.Id
    where p.PostTypeId in (1, 2)
),
AnswersRankedByScore as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate) as rnk
    from Posts p
    where p.PostTypeId = 2
),
RecentPostEdits as (
    select
        p.Id as PostId,
        ph.CreationDate,
        ph.UserId,
        u.DisplayName,
        ph.PostHistoryTypeId,
        ph.Comment,
        row_number() over (partition by p.Id order by ph.CreationDate desc) as rn
    from Posts p
    join PostHistory ph on ph.PostId = p.Id
    left join Users u on ph.UserId = u.Id
    where ph.PostHistoryTypeId in (4, 5, 6)
),
PostsWithBestAnswerAndEdits as (
    select
        p.Id,
        p.Title,
        p.OwnerDisplayName,
        p.Score, 
        p.ViewCount,
        p.Tags,
        a.Id as TopAnswerId,
        a.Score as TopAnswerScore,
        re.CreationDate as LastEditDate,
        re.DisplayName as LastEditor,
        -- Complex STRING manipulation examples:
        replace(
           substr(coalesce(nullif(p.Title, ''), ''), 1, 50) 
            || ' >>><>[' || coalesce(left(re.DisplayName, 10)::text, 'Unknown') || ']['
            || coalesce((select string_agg(b.Name, ', ') from Badges b where b.UserId = p.OwnerUserId and b.Date > '2023-01-01'), '-NoRecentBadges-') 
            || ']', '<>', ''
         ) as FancyDesc
    from PostsWithOwner p
    left join AnswersRankedByScore a on a.ParentId = p.Id and a.rnk = 1
    left join RecentPostEdits re on re.PostId = p.Id and re.rn = 1
),
UsersActiveIn2023 as (
    select
        u.Id,
        u.DisplayName,
        count(p.Id) filter (where p.CreationDate >= '2023-01-01') as RecentPostsCount,
        count(c.Id) filter (where c.CreationDate >= '2023-01-01') as RecentCommentsCount,
        count(case when ph.PostHistoryTypeId = 10 then 1 end) as NumNewClosures,
        dense_rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= '2023-01-01'
    left join Comments c on c.UserId = u.Id and c.CreationDate >= '2023-01-01'
    left join PostHistory ph on ph.UserId = u.Id and ph.CreationDate >= '2023-01-01'
    group by u.Id, u.DisplayName, u.Reputation
),
ClosedQuestionsByReason as (
    select
        p.Id as QuestionId,
        crt.Name as CloseReasonName,
        ph.Comment as CloseReasonData
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as smallint)
    where p.PostTypeId = 1
),
FilteredPosts as (
    select
        p.*,
        case 
          when p.Tags is not null and position('sql' in lower(p.Tags)) > 0 then true
          else false
          end as HasSqlTag
    from Posts p
    where p.CreationDate > '2022-01-01'
      and (p.Score > 5 or p.ViewCount > 1000 or p.FavoriteCount > 0)
),
FinalSet as (
    select p.Title, p.Id, p.FancyDesc,
        u.DisplayName as RecentActiveUser,
        u.RecentPostsCount, u.RecentCommentsCount, u.NumNewClosures, u.ReputationRank,
        crt.CloseReasonName,
        plist.HasSqlTag,
        row_number() over (partition by crt.CloseReasonName order by p.Score desc nulls last, p.FavoriteCount desc nulls last) as position_in_reason
    from PostsWithBestAnswerAndEdits p
    left join UsersActiveIn2023 u on u.Id = p.TopAnswerId -- intentionally mismatched join to generate NULLs
    left join ClosedQuestionsByReason crt on crt.QuestionId = p.Id
    join FilteredPosts plist on p.Id = plist.Id
    where (p.Score > 10 or p.ViewCount > 2000 or p.OwnerDisplayName is not null)
),
LegendCount as (
    select
      count(*) as TotalQuestions,
      count(distinct Id) filter (where HasSqlTag) as QuestionsWithSqlTag,
      count(*) filter (where CloseReasonName = 'Duplicate') as DuplicateClosed
    from FinalSet
)
select 
    fs.*,
    lc.TotalQuestions,
    lc.QuestionsWithSqlTag,
    lc.DuplicateClosed
from FinalSet fs
cross join LegendCount lc
where fs.position_in_reason <= 5
order by fs.CloseReasonName nulls first, fs.Score desc, fs.FavoriteCount desc
limit 50;