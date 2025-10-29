-- {"query": "2547.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1747} 
with recursive UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        row_number() over (order by u.Reputation desc, u.Id) as ReputationRank
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats as (
    select
        p.OwnerUserId,
        count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
        count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
        sum(case when p.PostTypeId = 1 then coalesce(p.Score,0) else 0 end) as TotalQuestionScore,
        sum(case when p.PostTypeId = 2 then coalesce(p.Score,0) else 0 end) as TotalAnswerScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopActivePosts as (
    select
        p.Id,
        p.Title,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        rank() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as ScoreRank
    from Posts p
    where p.PostTypeId in (1, 2)
        and p.Score > 10
        and p.CreationDate > (current_timestamp - interval '1 year')
),
PostInteractions as (
    select
        p.Id as PostId,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(v.UpVotes, 0) as UpVotes,
        coalesce(v.DownVotes, 0) as DownVotes,
        coalesce(pl.LinkedCount, 0) as LinkedPostsCount,
        coalesce(ph.EditCount, 0) as EditCount
    from Posts p
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select PostId,
               sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
               sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by PostId
    ) v on v.PostId = p.Id
    left join (
        select PostId, count(*) as LinkedCount
        from PostLinks
        group by PostId
    ) pl on pl.PostId = p.Id
    left join (
        select PostId, count(*) as EditCount
        from PostHistory
        where PostHistoryTypeId in (4,5,6,7,8,9,24)
        group by PostId
    ) ph on ph.PostId = p.Id
),
DuplicatedPosts as (
    select pl.PostId, count(distinct pl.RelatedPostId) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
    group by pl.PostId
),
UserTopTags as (
    select
        p.OwnerUserId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as Tag,
        count(*) as PostCount
    from Posts p
    where p.Tags is not null and p.OwnerUserId is not null and p.PostTypeId = 1
    group by p.OwnerUserId, Tag
),
RankedUserTags as (
    select
        ut.OwnerUserId,
        ut.Tag,
        ut.PostCount,
        rank() over (partition by ut.OwnerUserId order by ut.PostCount desc) as TagRank
    from UserTopTags ut
),
FilteredUserTags as (
    select OwnerUserId, Tag, PostCount
    from RankedUserTags
    where TagRank <= 3
),
UserDetails as (
    select
        ubs.UserId,
        ubs.DisplayName,
        ubs.Reputation,
        ubs.GoldBadges,
        ubs.SilverBadges,
        ubs.BronzeBadges,
        coalesce(qas.QuestionCount,0) as QuestionCount,
        coalesce(qas.AnswerCount,0) as AnswerCount,
        coalesce(qas.TotalQuestionScore,0) as TotalQuestionScore,
        coalesce(qas.TotalAnswerScore,0) as TotalAnswerScore,
        array_agg(distinct fut.Tag) filter (where fut.Tag is not null) as TopTags
    from UserBadgeStats ubs
    left join QuestionAnswerStats qas on qas.OwnerUserId = ubs.UserId
    left join FilteredUserTags fut on fut.OwnerUserId = ubs.UserId
    group by ubs.UserId, ubs.DisplayName, ubs.Reputation, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges,
        qas.QuestionCount, qas.AnswerCount, qas.TotalQuestionScore, qas.TotalAnswerScore
),
ComplexPosts as (
    select
        tp.Id,
        tp.Title,
        tp.PostTypeId,
        tp.OwnerUserId,
        u.DisplayName as OwnerName,
        pi.CommentCount,
        pi.UpVotes,
        pi.DownVotes,
        coalesce(dp.DuplicateCount, 0) as DuplicateCount,
        pi.LinkedPostsCount,
        pi.EditCount,
        -- complex calculation with NULL logic and CASE
        case 
            when pi.UpVotes + pi.DownVotes = 0 then null
            else round(cast(pi.UpVotes as numeric) / nullif(pi.UpVotes+pi.DownVotes, 0), 2)
        end as UpVoteRatio,
        row_number() over (partition by tp.PostTypeId order by tp.Score desc nulls last, tp.ViewCount desc nulls last) as PostRank,
        -- correlated subquery for last comment date
        (select max(c2.CreationDate) 
         from Comments c2 
         where c2.PostId = tp.Id) as LastCommentDate,
        -- string expression combining tags and title length
        coalesce(tp.Tags, '') || ' | LenTitle:' || length(coalesce(tp.Title, '')) as TagTitleInfo
    from TopActivePosts tp
    left join Posts p on p.Id = tp.Id
    left join Users u on u.Id = tp.OwnerUserId
    left join PostInteractions pi on pi.PostId = tp.Id
    left join DuplicatedPosts dp on dp.PostId = tp.Id
)
select
    ud.UserId,
    ud.DisplayName,
    ud.Reputation,
    ud.GoldBadges,
    ud.SilverBadges,
    ud.BronzeBadges,
    ud.QuestionCount,
    ud.AnswerCount,
    ud.TotalQuestionScore,
    ud.TotalAnswerScore,
    coalesce(array_to_string(ud.TopTags, ','), '(none)') as TopTags,
    cp.Id as PostId,
    cp.Title as PostTitle,
    case cp.PostTypeId when 1 then 'Question' when 2 then 'Answer' else 'Other' end as PostType,
    cp.CommentCount,
    cp.UpVotes,
    cp.DownVotes,
    cp.DuplicateCount,
    cp.LinkedPostsCount,
    cp.EditCount,
    cp.UpVoteRatio,
    cp.PostRank,
    cp.LastCommentDate,
    cp.TagTitleInfo
from UserDetails ud
left join ComplexPosts cp on cp.OwnerUserId = ud.UserId
where ud.Reputation > 5000
  and (cp.PostRank is null or cp.PostRank <= 5)
order by ud.Reputation desc, cp.PostRank nulls last
limit 100;