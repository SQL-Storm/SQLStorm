-- {"query": "1096.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1664} 
with RecursivePosts as (
    select
        p.Id,
        p.PostTypeId,
        p.AcceptedAnswerId,
        p.ParentId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Title,
        0 as Level,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select
        c.Id,
        c.PostTypeId,
        c.AcceptedAnswerId,
        c.ParentId,
        c.CreationDate,
        c.Score,
        c.ViewCount,
        c.OwnerUserId,
        c.Title,
        rp.Level + 1,
        rp.Path || c.Id
    from Posts c
    join RecursivePosts rp on c.ParentId = rp.Id
    where c.PostTypeId in (2,8) -- answers or privilege wiki posts
),
UserReputations as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.WebsiteUrl,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as TotalUpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as TotalDownVotes,
        rank() over (order by u.Reputation desc) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.WebsiteUrl
),
PostStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        coalesce(ph.PostHistoryTypeId, 0) as LastHistoryType,
        ph.CreationDate as LastEditDate,
        count(c.Id) as CommentTotal,
        string_agg(distinct coalesce(u.DisplayName, p.OwnerDisplayName), ',' order by coalesce(u.DisplayName, p.OwnerDisplayName)) as Contributors
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.CreationDate = (
        select max(ph2.CreationDate)
        from PostHistory ph2
        where ph2.PostId = p.Id
    )
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = c.UserId
    group by p.Id, p.PostTypeId, p.OwnerUserId, p.Title, p.Tags, p.CreationDate, p.Score, p.ViewCount, p.AnswerCount, p.CommentCount, p.FavoriteCount, ph.PostHistoryTypeId, ph.CreationDate, p.OwnerDisplayName
),
TagStats as (
    select
        t.Id,
        t.TagName,
        t.Count,
        coalesce(excerpt.Title, '') as ExcerptTitle,
        coalesce(wiki.Title, '') as WikiTitle,
        t.IsModeratorOnly,
        t.IsRequired,
        (select count(*) from Posts p where p.Tags like '%' || concat('<', t.TagName, '>') || '%') as PostCountWithTag
    from Tags t
    left join Posts excerpt on excerpt.Id = t.ExcerptPostId
    left join Posts wiki on wiki.Id = t.WikiPostId
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle,
        pl.CreationDate
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- duplicates
),
TopAnsweredQuestions as (
    select
        p.Id,
        p.Title,
        p.AnswerCount,
        p.ViewCount,
        p.Score,
        row_number() over (order by p.AnswerCount desc, p.ViewCount desc) as AnswerRank
    from Posts p
    where p.PostTypeId = 1
    and p.CreationDate >= (current_date - interval '1 year')
),
LastVotesPerPost as (
    select
        v.PostId,
        v.VoteTypeId,
        v.CreationDate,
        row_number() over (partition by v.PostId, v.VoteTypeId order by v.CreationDate desc) as VoteRank
    from Votes v
)
select
    up.Id as UserId,
    up.DisplayName,
    up.Reputation,
    up.GoldBadges,
    up.SilverBadges,
    up.BronzeBadges,
    up.TotalUpVotes,
    up.TotalDownVotes,
    up.ReputationRank,
    ps.Id as PostId,
    ps.Title as PostTitle,
    ps.PostTypeId,
    ps.Score,
    ps.ViewCount,
    ps.AnswerCount,
    ps.FavoriteCount,
    ps.LastHistoryType,
    ps.LastEditDate,
    ps.CommentTotal,
    ps.Contributors,
    ts.TagName,
    ts.Count as TagUsageCount,
    ts.PostCountWithTag,
    ts.IsModeratorOnly,
    ts.IsRequired,
    dl.RelatedPostId as DuplicateOfPostId,
    dl.RelatedPostTitle as DuplicateOfTitle,
    ta.AnswerRank,
    lv.VoteTypeId as LastVoteTypeId,
    lv.CreationDate as LastVoteDate,
    coalesce(
        (select count(*) from Comments c2 where c2.PostId = ps.Id and length(trim(c2.Text)) > 200),
        0
    ) as LongCommentsCount,
    case
        when ps.Score < 0 then 'Negative Score'
        when ps.Score = 0 then 'Neutral Score'
        else 'Positive Score'
    end as ScoreCategory,
    case
        when ps.AnswerCount >= 10 then 'Highly Answered'
        when ps.AnswerCount > 0 then 'Moderately Answered'
        else 'Unanswered'
    end as AnswerCountCategory,
    concat_ws(' | ',
        substring(ps.Title from 1 for 50),
        coalesce(ts.TagName, 'NoTag'),
        'User: ' || coalesce(up.DisplayName, 'Unknown'),
        'Score ' || ps.Score::text,
        case when ps.FavoriteCount > 0 then '★' else '' end
    ) as PostSummary
from UserReputations up
left join PostStats ps on ps.OwnerUserId = up.Id
left join TagStats ts on ps.Tags is not null and ts.TagName = (regexp_split_to_table(ps.Tags, E'[><]')) limit 1
left join DuplicateLinks dl on dl.PostId = ps.Id
left join TopAnsweredQuestions ta on ta.Id = ps.Id
left join LastVotesPerPost lv on lv.PostId = ps.Id and lv.VoteRank = 1
where up.Reputation > 1000
and (ps.PostTypeId = 1 or ps.PostTypeId is null)
and (
    ps.CreationDate > (now() - interval '2 years')
    or ps.CreationDate is null
)
order by up.ReputationRank, ps.Score desc nulls last, ps.ViewCount desc nulls last
limit 100;