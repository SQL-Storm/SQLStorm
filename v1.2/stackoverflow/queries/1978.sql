with CommentKeyWords as (
    select
        c.Id,
        -- build keyword array per comment using aggregation in a grouped subquery
        kw.KeywordArray,
        c.Text,
        c.PostId,
        est.SubQueryRank
    from
        Comments c
        cross join lateral unnest(regexp_split_to_array(regexp_replace(c.Text, '[^a-zA-Z0-9 ]+', '', 'g'), ' ')) as _word(word)
        join (
            select
                id as Id,
                SubQueryRank
            from
                (values (1, 1)) v(id, SubQueryRank)
        ) est
            on est.Id = c.Id
        left join (
            select
                c2.Id,
                array_agg(lower(w.word)) filter (where char_length(w.word) > 3) as KeywordArray
            from
                Comments c2
                cross join lateral unnest(regexp_split_to_array(regexp_replace(c2.Text, '[^a-zA-Z0-9 ]+', '', 'g'), ' ')) as w(word)
            group by
                c2.Id
        ) kw on kw.Id = c.Id
)
select
    Id,
    KeywordArray,
    Text,
    PostId,
    SubQueryRank
from
    CommentKeyWords
group by
    Id,
    KeywordArray,
    Text,
    PostId,
    SubQueryRank;