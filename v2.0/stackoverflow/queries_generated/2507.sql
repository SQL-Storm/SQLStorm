-- {"query": "2507.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 2000} 
with RecursiveCTE as (
    select 
        p.Id as PostId,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        1 as Level,
        array[p.Id] as Path
    from Posts p
    where p.PostTypeId = 1 -- questions only
    union all
    select 
        a.Id,
        a.PostTypeId,
        a.OwnerUserId,
        a.CreationDate,
        a.Score,
        a.ViewCount,
        a.Tags,
        r.Level + 1,
        Path || a.Id
    from Posts a
    join RecursiveCTE r on a.ParentId = r.PostId
    where a.PostTypeId = 2 -- answers only
      and not a.Id = any(r.Path)
),
UserBadgeRanks AS (
    select
        u.Id as UserId,
        u.DisplayName,
        b.Class,
        count(*) as BadgeCount
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, b.Class
),
PostCommentStats AS (
    select
        p.Id as PostId,
        count(distinct c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(nullif(c.UserDisplayName, ''), 'Anonymous'), ', ') as CommenterNames
    from Posts p
    left join Comments c on c.PostId = p.Id
    group by p.Id
),
QuestionAnswerVotes AS (
    select 
        q.Id as QuestionId,
        coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end), 0) as QuestionUpVotes,
        coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end), 0) as QuestionDownVotes,
        count(distinct a.Id) as AnswerCount,
        coalesce(sum(a.Score), 0) as AnswerScoreSum,
        coalesce(sum(case when av.VoteTypeId = 2 then 1 else 0 end), 0) as AnswerUpVotes,
        coalesce(sum(case when av.VoteTypeId = 3 then 1 else 0 end), 0) as AnswerDownVotes
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    left join Votes v on v.PostId = q.Id
    left join Votes av on av.PostId = a.Id
    where q.PostTypeId = 1
    group by q.Id
),
RecentPostHistories AS (
    select distinct on (ph.PostId)
        ph.PostId,
        ph.CreationDate,
        ph.PostHistoryTypeId,
        ph.Comment as CloseReason,
        ph.UserId,
        ph.UserDisplayName
    from PostHistory ph
    where ph.PostHistoryTypeId in (10, 11)  -- Closed or Reopened
    order by ph.PostId, ph.CreationDate desc
),
UserActivityWindow AS (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        count(p.Id) filter (where p.PostTypeId = 1) over (partition by u.Id) as QuestionPosts,
        count(p.Id) filter (where p.PostTypeId = 2) over (partition by u.Id) as AnswerPosts,
        row_number() over (partition by u.Id order by p.CreationDate desc) as RecentPostRank,
        avg(p.Score) over (partition by u.Id) as AveragePostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
),
DuplicateLinks AS (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        p1.Title as PostTitle,
        p2.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p1 on p1.Id = pl.PostId
    join Posts p2 on p2.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicates
),
FinalAggregated AS (
    select
        q.Id as QuestionId,
        q.Title,
        q.CreationDate,
        q.Score,
        q.ViewCount,
        q.Tags,
        coalesce(qav.QuestionUpVotes,0) as QUpVotes,
        coalesce(qav.QuestionDownVotes,0) as QDownVotes,
        coalesce(qav.AnswerCount,0) as AnswerCount,
        coalesce(qav.AnswerScoreSum,0) as AnswerScore,
        coalesce(qav.AnswerUpVotes,0) as AnswerUpVotes,
        coalesce(qav.AnswerDownVotes,0) as AnswerDownVotes,
        pcs.CommentCount,
        pcs.LastCommentDate,
        pcs.CommenterNames,
        rph.PostHistoryTypeId,
        rph.CloseReason,
        u.DisplayName as OwnerName,
        u.Reputation as OwnerReputation,
        u.CreationDate as OwnerCreationDate,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        string_agg(distinct dt.Name, ', ') as PostHistoryTypeNames,
        array_length(string_to_array(q.Tags, '><'),1) as TagCount
    from Posts q
    left join QuestionAnswerVotes qav on qav.QuestionId = q.Id
    left join PostCommentStats pcs on pcs.PostId = q.Id
    left join RecentPostHistories rph on rph.PostId = q.Id
    left join Users u on u.Id = q.OwnerUserId
    left join (
       select UserId,
           count(*) filter (where Class = 1) as GoldBadges,
           count(*) filter (where Class = 2) as SilverBadges,
           count(*) filter (where Class = 3) as BronzeBadges
       from Badges
       group by UserId
    ) ub on ub.UserId = q.OwnerUserId
    left join LATERAL (
        select distinct ph.Name
        from PostHistoryTypes ph
        join PostHistory pht on pht.PostHistoryTypeId = ph.Id and pht.PostId = q.Id
    ) dt on true
    where q.PostTypeId = 1
    group by q.Id, q.Title, q.CreationDate, q.Score, q.ViewCount, q.Tags, qav.QuestionUpVotes, qav.QuestionDownVotes,
        qav.AnswerCount, qav.AnswerScoreSum, qav.AnswerUpVotes, qav.AnswerDownVotes,
        pcs.CommentCount, pcs.LastCommentDate, pcs.CommenterNames,
        rph.PostHistoryTypeId, rph.CloseReason,
        u.DisplayName, u.Reputation, u.CreationDate,
        ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges
)
select 
    fa.QuestionId,
    fa.Title,
    fa.CreationDate,
    fa.Score,
    fa.ViewCount,
    fa.QUpVotes,
    fa.QDownVotes,
    fa.AnswerCount,
    fa.AnswerScore,
    fa.AnswerUpVotes,
    fa.AnswerDownVotes,
    fa.CommentCount,
    fa.LastCommentDate,
    left(fa.CommenterNames, 100) as CommenterNamesSample,
    coalesce(fa.PostHistoryTypeId, 0) as LastPostHistoryTypeId,
    case when fa.CloseReason is not null then fa.CloseReason else 'Open' end as CloseStatus,
    fa.OwnerName,
    fa.OwnerReputation,
    fa.OwnerCreationDate,
    coalesce(fa.GoldBadges, 0) as GoldBadges,
    coalesce(fa.SilverBadges, 0) as SilverBadges,
    coalesce(fa.BronzeBadges, 0) as BronzeBadges,
    fa.PostHistoryTypeNames,
    fa.TagCount,
    case 
        when fa.Score > 10 and fa.ViewCount > 1000 then 'Hot Question' 
        when fa.Score <= 0 then 'Low Quality' 
        else 'Normal' 
    end as QuestionStatus,
    (select count(*) from DuplicateLinks dl where dl.PostId = fa.QuestionId) as DuplicateCount,
    -- complex string manipulation: tags lower case and alphabetical
    array_to_string(array_agg(distinct lower(trim(tag)) order by lower(trim(tag))), ', ') as NormalizedTags
from FinalAggregated fa
left join lateral (
    select unnest(string_to_array(fa.Tags, '><')) as tag
) t on true
group by
    fa.QuestionId, fa.Title, fa.CreationDate, fa.Score, fa.ViewCount, fa.QUpVotes, fa.QDownVotes,
    fa.AnswerCount, fa.AnswerScore, fa.AnswerUpVotes, fa.AnswerDownVotes, fa.CommentCount,
    fa.LastCommentDate, fa.CommenterNames, fa.PostHistoryTypeId, fa.CloseReason,
    fa.OwnerName, fa.OwnerReputation, fa.OwnerCreationDate, fa.GoldBadges, fa.SilverBadges,
    fa.BronzeBadges, fa.PostHistoryTypeNames, fa.TagCount
order by fa.Score desc NULLS LAST, fa.ViewCount desc NULLS LAST
limit 50;